function apiErrorMessage(data, status) {
  return data?.error?.message || data?.message || `模型请求失败（HTTP ${status}）`;
}

function isFormatUnavailable(message) {
  return /(response_format|json_schema|structured output|text\.format).*(unavailable|unsupported|not supported|not available|invalid|unknown)|this response_format type is unavailable now/i.test(
    String(message || ""),
  );
}

function isResponsesEndpointUnavailable(message, status) {
  return (
    [404, 405, 501].includes(status) ||
    /(responses api|\/responses|endpoint).*(unavailable|unsupported|not supported|not found|unknown)/i.test(
      String(message || ""),
    )
  );
}

function schemaInstructions(payload) {
  return `${payload.instructions}

你必须只返回一个可被 JSON.parse 直接解析的 JSON 值，不要输出 Markdown 代码块、解释或前后缀。
输出必须严格匹配以下 JSON Schema：
${JSON.stringify(payload.schema)}`;
}

function parseStructuredText(value) {
  if (typeof value !== "string" || !value.trim()) {
    throw new Error("模型没有返回可解析的结构化内容");
  }
  const stripped = value
    .trim()
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim();
  try {
    return JSON.parse(stripped);
  } catch {
    const objectStart = stripped.indexOf("{");
    const arrayStart = stripped.indexOf("[");
    const starts = [objectStart, arrayStart].filter((index) => index >= 0);
    const start = starts.length ? Math.min(...starts) : -1;
    const objectEnd = stripped.lastIndexOf("}");
    const arrayEnd = stripped.lastIndexOf("]");
    const end = Math.max(objectEnd, arrayEnd);
    if (start >= 0 && end > start) {
      try {
        return JSON.parse(stripped.slice(start, end + 1));
      } catch {
        // Fall through to the stable user-facing error below.
      }
    }
    throw new Error("模型响应不是有效 JSON；已尝试兼容纯文本结构化输出");
  }
}

function schemaValidationErrors(value, schema, path = "$") {
  const errors = [];
  if (!schema || typeof schema !== "object") return errors;
  if (schema.type === "object") {
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      return [`${path} 应为对象`];
    }
    for (const key of schema.required || []) {
      if (!(key in value)) errors.push(`${path}.${key} 缺失`);
    }
    for (const [key, childSchema] of Object.entries(schema.properties || {})) {
      if (key in value) {
        errors.push(
          ...schemaValidationErrors(value[key], childSchema, `${path}.${key}`),
        );
      }
    }
  } else if (schema.type === "array") {
    if (!Array.isArray(value)) return [`${path} 应为数组`];
    if (Number.isFinite(schema.minItems) && value.length < schema.minItems) {
      errors.push(`${path} 至少需要 ${schema.minItems} 项，实际 ${value.length} 项`);
    }
    if (Number.isFinite(schema.maxItems) && value.length > schema.maxItems) {
      errors.push(`${path} 最多允许 ${schema.maxItems} 项，实际 ${value.length} 项`);
    }
    value.forEach((item, index) => {
      errors.push(
        ...schemaValidationErrors(item, schema.items, `${path}[${index}]`),
      );
    });
  } else if (schema.type === "string") {
    if (typeof value !== "string") return [`${path} 应为字符串`];
    if (Number.isFinite(schema.minLength) && value.length < schema.minLength) {
      errors.push(`${path} 至少需要 ${schema.minLength} 个字符`);
    }
    if (Number.isFinite(schema.maxLength) && value.length > schema.maxLength) {
      errors.push(`${path} 最多允许 ${schema.maxLength} 个字符`);
    }
  } else if (schema.type === "integer") {
    if (!Number.isInteger(value)) {
      errors.push(`${path} 应为整数`);
    } else {
      if (Number.isFinite(schema.minimum) && value < schema.minimum) {
        errors.push(`${path} 不得小于 ${schema.minimum}`);
      }
      if (Number.isFinite(schema.maximum) && value > schema.maximum) {
        errors.push(`${path} 不得大于 ${schema.maximum}`);
      }
    }
  } else if (schema.type === "number") {
    if (typeof value !== "number" || !Number.isFinite(value)) {
      errors.push(`${path} 应为数字`);
    } else {
      if (Number.isFinite(schema.minimum) && value < schema.minimum) {
        errors.push(`${path} 不得小于 ${schema.minimum}`);
      }
      if (Number.isFinite(schema.maximum) && value > schema.maximum) {
        errors.push(`${path} 不得大于 ${schema.maximum}`);
      }
    }
  }
  return errors;
}

function parseAndValidateStructuredText(value, schema) {
  const parsed = parseStructuredText(value);
  const errors = schemaValidationErrors(parsed, schema);
  if (errors.length) {
    throw new Error(`模型 JSON 结构不完整：${errors.slice(0, 4).join("；")}`);
  }
  return parsed;
}

function responsesOutputText(data) {
  return (
    data?.output_text ||
    data?.output
      ?.flatMap((item) => item.content || [])
      ?.find((item) => item.type === "output_text")
      ?.text
  );
}

function chatOutputText(data) {
  const content = data?.choices?.[0]?.message?.content;
  if (typeof content === "string") return content;
  if (Array.isArray(content)) {
    return content
      .map((item) => item?.text || item?.content || "")
      .filter(Boolean)
      .join("");
  }
  return "";
}

async function requestChatStructured({
  fetchImpl,
  endpoint,
  headers,
  model,
  payload,
}) {
  const messages = [
    { role: "system", content: payload.instructions },
    { role: "user", content: payload.input },
  ];
  const schemaMessages = [
    { role: "system", content: schemaInstructions(payload) },
    { role: "user", content: payload.input },
  ];
  const attempts = [
    {
      model,
      messages,
      response_format: {
        type: "json_schema",
        json_schema: {
          name: payload.name,
          strict: true,
          schema: payload.schema,
        },
      },
    },
    {
      model,
      messages: schemaMessages,
      response_format: { type: "json_object" },
    },
    {
      model,
      messages: schemaMessages,
    },
  ];

  let lastMessage = "";
  for (let index = 0; index < attempts.length; index += 1) {
    const response = await fetchImpl(endpoint, {
      method: "POST",
      headers,
      body: JSON.stringify(attempts[index]),
    });
    const data = await response.json().catch(() => ({}));
    if (response.ok) {
      try {
        return parseAndValidateStructuredText(
          chatOutputText(data),
          payload.schema,
        );
      } catch (error) {
        lastMessage =
          error instanceof Error ? error.message : "模型 JSON 结构不完整";
        if (index < attempts.length - 1) continue;
        throw error;
      }
    }
    lastMessage = apiErrorMessage(data, response.status);
    const canFallback =
      index < attempts.length - 1 &&
      (isFormatUnavailable(lastMessage) || [400, 404, 422].includes(response.status));
    if (!canFallback) throw new Error(lastMessage);
  }
  throw new Error(lastMessage || "模型结构化输出调用失败");
}

module.exports = {
  apiErrorMessage,
  chatOutputText,
  isFormatUnavailable,
  isResponsesEndpointUnavailable,
  parseStructuredText,
  parseAndValidateStructuredText,
  requestChatStructured,
  responsesOutputText,
  schemaInstructions,
  schemaValidationErrors,
};

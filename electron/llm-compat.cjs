function apiErrorMessage(data, status) {
  return data?.error?.message || data?.message || `Model request failed (HTTP ${status})`;
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

Return only one JSON value that JSON.parse can parse directly. Do not include Markdown fences, explanations, prefixes, or suffixes.
The output must match this JSON Schema exactly:
${JSON.stringify(payload.schema)}`;
}

function parseStructuredText(value) {
  if (typeof value !== "string" || !value.trim()) {
    throw new Error("The model returned no readable structured content.");
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
    throw new Error("The model response is not valid JSON. Plain-text compatibility parsing also failed.");
  }
}

function schemaValidationErrors(value, schema, path = "$") {
  const errors = [];
  if (!schema || typeof schema !== "object") return errors;
  if (schema.type === "object") {
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      return [`${path} must be an object`];
    }
    for (const key of schema.required || []) {
      if (!(key in value)) errors.push(`${path}.${key} is missing`);
    }
    for (const [key, childSchema] of Object.entries(schema.properties || {})) {
      if (key in value) {
        errors.push(
          ...schemaValidationErrors(value[key], childSchema, `${path}.${key}`),
        );
      }
    }
  } else if (schema.type === "array") {
    if (!Array.isArray(value)) return [`${path} must be an array`];
    if (Number.isFinite(schema.minItems) && value.length < schema.minItems) {
      errors.push(`${path} requires at least ${schema.minItems} items; received ${value.length}`);
    }
    if (Number.isFinite(schema.maxItems) && value.length > schema.maxItems) {
      errors.push(`${path} allows at most ${schema.maxItems} items; received ${value.length}`);
    }
    value.forEach((item, index) => {
      errors.push(
        ...schemaValidationErrors(item, schema.items, `${path}[${index}]`),
      );
    });
  } else if (schema.type === "string") {
    if (typeof value !== "string") return [`${path} must be a string`];
    if (Number.isFinite(schema.minLength) && value.length < schema.minLength) {
      errors.push(`${path} requires at least ${schema.minLength} characters`);
    }
    if (Number.isFinite(schema.maxLength) && value.length > schema.maxLength) {
      errors.push(`${path} allows at most ${schema.maxLength} characters`);
    }
  } else if (schema.type === "integer") {
    if (!Number.isInteger(value)) {
      errors.push(`${path} must be an integer`);
    } else {
      if (Number.isFinite(schema.minimum) && value < schema.minimum) {
        errors.push(`${path} must be at least ${schema.minimum}`);
      }
      if (Number.isFinite(schema.maximum) && value > schema.maximum) {
        errors.push(`${path} must be at most ${schema.maximum}`);
      }
    }
  } else if (schema.type === "number") {
    if (typeof value !== "number" || !Number.isFinite(value)) {
      errors.push(`${path} must be a number`);
    } else {
      if (Number.isFinite(schema.minimum) && value < schema.minimum) {
        errors.push(`${path} must be at least ${schema.minimum}`);
      }
      if (Number.isFinite(schema.maximum) && value > schema.maximum) {
        errors.push(`${path} must be at most ${schema.maximum}`);
      }
    }
  }
  return errors;
}

function parseAndValidateStructuredText(value, schema) {
  const parsed = parseStructuredText(value);
  const errors = schemaValidationErrors(parsed, schema);
  if (errors.length) {
    throw new Error(`Model JSON is incomplete: ${errors.slice(0, 4).join("; ")}`);
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
  const schemaMessages = [
    { role: "system", content: schemaInstructions(payload) },
    { role: "user", content: payload.input },
  ];
  const response = await fetchImpl(endpoint, {
    method: "POST",
    headers,
    body: JSON.stringify({
      model,
      messages: schemaMessages,
      response_format: {
        type: "json_schema",
        json_schema: { name: payload.name, strict: true, schema: payload.schema },
      },
    }),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(apiErrorMessage(data, response.status));
  return parseAndValidateStructuredText(chatOutputText(data), payload.schema);
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

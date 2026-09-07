import { createRequire } from "node:module";
import { describe, expect, it } from "vitest";
import { episodeTransportSchema } from "../src/pipeline/online";

const require = createRequire(import.meta.url);
const compat = require("../electron/llm-compat.cjs") as {
  apiErrorMessage: (data: unknown, status: number) => string;
  authHeaders: (
    mode: "bearer" | "api-key" | "x-api-key" | "x-goog-api-key" | "none",
    apiKey: string,
  ) => Record<string, string>;
  isFormatUnavailable: (message: string) => boolean;
  parseStructuredText: (value: string) => unknown;
  parseAndValidateStructuredText: (
    value: string,
    schema: Record<string, unknown>,
  ) => unknown;
  requestChatStructured: (options: {
    fetchImpl: typeof fetch;
    endpoint: string;
    headers: Record<string, string>;
    model: string;
    payload: {
      instructions: string;
      input: string;
      name: string;
      schema: Record<string, unknown>;
    };
    structuredOutput?: "json_schema" | "json_object" | "prompt_only";
  }) => Promise<unknown>;
  responsesTextFormat: (
    mode: "json_schema" | "json_object" | "prompt_only",
    payload: { name: string; schema: Record<string, unknown> },
  ) => Record<string, unknown> | undefined;
  schemaInstructions: (payload: {
    instructions: string;
    schema: Record<string, unknown>;
  }) => string;
};

describe("LLM structured-output compatibility", () => {
  const payload = {
    instructions: "Return a title.",
    input: "Novel",
    name: "title",
    schema: {
      type: "object",
      required: ["title"],
      properties: { title: { type: "string" } },
    },
  };

  const successfulFetch = (bodies: Array<Record<string, unknown>>) =>
    (async (_url: string, init?: RequestInit) => {
      bodies.push(JSON.parse(String(init?.body)));
      return new Response(
        JSON.stringify({ choices: [{ message: { content: '{"title":"ok"}' } }] }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    }) as typeof fetch;

  it("surfaces the actual OpenRouter provider error from metadata.raw", () => {
    expect(
      compat.apiErrorMessage(
        {
          error: {
            message: "Provider returned error",
            code: 400,
            metadata: {
              raw: JSON.stringify({
                error: {
                  message: "Corrupted thought signature.",
                  status: "INVALID_ARGUMENT",
                },
              }),
              provider_name: "Google AI Studio",
            },
          },
        },
        400,
      ),
    ).toBe("[Google AI Studio] Corrupted thought signature.");
  });

  it("keeps the HTTP status when a provider returns no useful details", () => {
    expect(
      compat.apiErrorMessage(
        { error: { message: "Provider returned error" } },
        502,
      ),
    ).toBe(
      "Provider returned error (HTTP 502). No additional error details were provided.",
    );
  });

  it("extracts validation messages from a provider issue list", () => {
    expect(
      compat.apiErrorMessage(
        {
          error: {
            message: "Provider returned error",
            metadata: {
              raw: JSON.stringify({
                issues: [
                  {
                    message:
                      "Unrecognized key in response_format: strict",
                  },
                ],
              }),
              provider_name: "Compatible Gateway",
            },
          },
        },
        400,
      ),
    ).toBe(
      "[Compatible Gateway] Unrecognized key in response_format: strict",
    );
  });

  it("recognizes the provider error reported by the desktop app", () => {
    expect(
      compat.isFormatUnavailable("This response_format type is unavailable now"),
    ).toBe(true);
  });

  it("parses JSON wrapped in a markdown fence", () => {
    expect(compat.parseStructuredText('```json\n{"ok":true}\n```')).toEqual({
      ok: true,
    });
  });

  it("adds the schema to prompt-only fallback instructions", () => {
    const prompt = compat.schemaInstructions({
      instructions: "Return an object.",
      schema: { type: "object", required: ["title"] },
    });
    expect(prompt).toContain("JSON.parse");
    expect(prompt).toContain('"required":["title"]');
  });

  it("builds supported authentication headers, including local no-auth services", () => {
    expect(compat.authHeaders("bearer", "secret")).toEqual({
      "Content-Type": "application/json",
      Authorization: "Bearer secret",
    });
    expect(compat.authHeaders("api-key", "secret")).toHaveProperty(
      "api-key",
      "secret",
    );
    expect(compat.authHeaders("x-api-key", "secret")).toHaveProperty(
      "x-api-key",
      "secret",
    );
    expect(compat.authHeaders("x-goog-api-key", "secret")).toHaveProperty(
      "x-goog-api-key",
      "secret",
    );
    expect(compat.authHeaders("none", "")).toEqual({
      "Content-Type": "application/json",
    });
    expect(() => compat.authHeaders("bearer", "")).toThrow(
      "No model API key",
    );
  });

  it("maps all Responses API structured-output modes without inventing a fallback", () => {
    expect(compat.responsesTextFormat("json_schema", payload)).toMatchObject({
      type: "json_schema",
      name: "title",
      strict: true,
    });
    expect(compat.responsesTextFormat("json_object", payload)).toEqual({
      type: "json_object",
    });
    expect(compat.responsesTextFormat("prompt_only", payload)).toBeUndefined();
  });

  it("supports chat json_object mode in one request", async () => {
    const bodies: Array<Record<string, unknown>> = [];
    await expect(
      compat.requestChatStructured({
        fetchImpl: successfulFetch(bodies),
        endpoint: "https://example.test/chat/completions",
        headers: {},
        model: "compatible-model",
        payload,
        structuredOutput: "json_object",
      }),
    ).resolves.toEqual({ title: "ok" });
    expect(bodies).toHaveLength(1);
    expect(bodies[0]).toHaveProperty("response_format.type", "json_object");
  });

  it("supports prompt-only chat mode without a response_format field", async () => {
    const bodies: Array<Record<string, unknown>> = [];
    await expect(
      compat.requestChatStructured({
        fetchImpl: successfulFetch(bodies),
        endpoint: "https://example.test/chat/completions",
        headers: {},
        model: "compatible-model",
        payload,
        structuredOutput: "prompt_only",
      }),
    ).resolves.toEqual({ title: "ok" });
    expect(bodies).toHaveLength(1);
    expect(bodies[0]).not.toHaveProperty("response_format");
    expect(bodies[0]).toHaveProperty("messages.0.content");
    expect(String((bodies[0].messages as Array<{ content: string }>)[0].content)).toContain(
      '"required":["title"]',
    );
  });

  it("surfaces plain-text gateway failures instead of hiding them", async () => {
    const fetchImpl = (async () =>
      new Response("Gateway quota exhausted", {
        status: 429,
        headers: { "Content-Type": "text/plain" },
      })) as typeof fetch;
    await expect(
      compat.requestChatStructured({
        fetchImpl,
        endpoint: "https://example.test/chat/completions",
        headers: {},
        model: "compatible-model",
        payload,
        structuredOutput: "prompt_only",
      }),
    ).rejects.toThrow("Gateway quota exhausted");
  });

  it("rejects JSON that omits a required dialogue array", () => {
    expect(() =>
      compat.parseAndValidateStructuredText(
        '{"scenes":[{"heading":"外景","location":"山门","action":"动作足够完整"}]}',
        {
          type: "object",
          required: ["scenes"],
          properties: {
            scenes: {
              type: "array",
              items: {
                type: "object",
                required: ["heading", "location", "action", "dialogue"],
                properties: {
                  heading: { type: "string" },
                  location: { type: "string" },
                  action: { type: "string" },
                  dialogue: { type: "array" },
                },
              },
            },
          },
        },
      ),
    ).toThrow("$.scenes[0].dialogue is missing");
  });

  it("rejects a model-planned scene count outside the runtime range", () => {
    expect(() =>
      compat.parseAndValidateStructuredText('{"sceneCount":8}', {
        type: "object",
        required: ["sceneCount"],
        properties: {
          sceneCount: {
            type: "integer",
            minimum: 1,
            maximum: 4,
          },
        },
      }),
    ).toThrow("$.sceneCount must be at most 4");
  });

  it("allows thin scene dialogue through transport validation for automatic repair", () => {
    const scene = (lineCount: number) => ({
      heading: "内景 偏殿 - 日",
      location: "宗门偏殿",
      action: "两人当面对峙。",
      dialogue: Array.from({ length: lineCount }, (_, index) => ({
        speaker: index % 2 ? "沈知雪" : "陈砚",
        text: index % 2 ? "你已经无路可退。" : "那就当众验清楚。",
      })),
    });
    const payload = { scenes: [scene(8), scene(6)] };
    expect(
      compat.parseAndValidateStructuredText(
        JSON.stringify(payload),
        episodeTransportSchema(),
      ),
    ).toEqual(payload);
  });

  it("does not issue automatic paid retries when json_schema is unavailable", async () => {
    const bodies: Array<Record<string, unknown>> = [];
    const fetchImpl = (async (_url: string, init?: RequestInit) => {
      bodies.push(JSON.parse(String(init?.body)));
      return new Response(
        JSON.stringify({
          error: { message: "This response_format type is unavailable now" },
        }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }) as typeof fetch;

    await expect(
      compat.requestChatStructured({
        fetchImpl,
        endpoint: "https://example.test/chat/completions",
        headers: { Authorization: "Bearer test" },
        model: "compatible-model",
        payload,
      }),
    ).rejects.toThrow("response_format type is unavailable");
    expect(bodies).toHaveLength(1);
    expect(bodies[0]).toHaveProperty("response_format.type", "json_schema");
  });
});

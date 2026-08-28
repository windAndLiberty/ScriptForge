import { createRequire } from "node:module";
import { describe, expect, it } from "vitest";
import { episodeTransportSchema } from "../src/pipeline/online";

const require = createRequire(import.meta.url);
const compat = require("../electron/llm-compat.cjs") as {
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
  }) => Promise<unknown>;
  schemaInstructions: (payload: {
    instructions: string;
    schema: Record<string, unknown>;
  }) => string;
};

describe("LLM structured-output compatibility", () => {
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
        payload: {
          instructions: "Return a title.",
          input: "Novel",
          name: "title",
          schema: { type: "object", required: ["title"] },
        },
      }),
    ).rejects.toThrow("response_format type is unavailable");
    expect(bodies).toHaveLength(1);
    expect(bodies[0]).toHaveProperty("response_format.type", "json_schema");
  });
});

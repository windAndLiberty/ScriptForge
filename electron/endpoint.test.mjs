import { describe, expect, it } from "vitest";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { normalizeApiRoot } = require("./endpoint.cjs");

describe("OpenAI-compatible API roots", () => {
  it("normalizes a valid root", () => {
    expect(normalizeApiRoot("https://api.openai.com/v1/")).toBe("https://api.openai.com/v1");
    expect(normalizeApiRoot("http://localhost:11434/v1")).toBe("http://localhost:11434/v1");
  });

  it("rejects request endpoints and dashboard/model URLs", () => {
    expect(() => normalizeApiRoot("https://example.com/v1/chat/completions")).toThrow("API root URL");
    expect(() => normalizeApiRoot("https://example.com/models/model-a")).toThrow("dashboard");
  });

  it("guides OpenRouter website URLs to the API host", () => {
    expect(() => normalizeApiRoot("https://openrouter.com/chat/completions")).toThrow("https://openrouter.ai/api/v1");
    expect(normalizeApiRoot("https://openrouter.ai/api/v1")).toBe("https://openrouter.ai/api/v1");
  });
});

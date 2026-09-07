function normalizeApiRoot(value) {
  const raw = String(value || "").trim();
  let url;
  try { url = new URL(raw); } catch { throw new Error("Enter a valid OpenAI-compatible API root URL."); }
  if (!["https:", "http:"].includes(url.protocol)) throw new Error("The API root URL must use HTTPS or HTTP.");
  const path = url.pathname.replace(/\/+$/, "");
  if (url.hostname === "openrouter.com" || url.hostname === "www.openrouter.com") {
    throw new Error("OpenRouter's API root is https://openrouter.ai/api/v1, not the openrouter.com website.");
  }
  if (/\/(chat\/completions|responses)$/i.test(path) || /\/(models?|dashboard)(\/|$)/i.test(path)) {
    throw new Error("Enter the OpenAI-compatible API root URL, not a request endpoint, dashboard, or model page URL.");
  }
  url.pathname = path || "/v1";
  url.hash = "";
  return url.toString().replace(/\/+$/, "");
}

function appendApiPath(baseUrl, suffix) {
  const url = new URL(baseUrl);
  const basePath = url.pathname.replace(/\/+$/, "");
  const childPath = String(suffix || "").replace(/^\/+/, "");
  url.pathname = `${basePath}/${childPath}`;
  url.hash = "";
  return url.toString();
}

module.exports = { appendApiPath, normalizeApiRoot };

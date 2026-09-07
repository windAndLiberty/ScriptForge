const { app, BrowserWindow, dialog, ipcMain, safeStorage } = require("electron");
const fs = require("node:fs/promises");
const path = require("node:path");
const { readDocument, SUPPORTED_EXTENSIONS } = require("./document-import.cjs");
const { ProjectStore } = require("./project-store.cjs");
const { appendApiPath, normalizeApiRoot } = require("./endpoint.cjs");
const { makeDocx } = require("./docx-export.cjs");
const {
  apiErrorMessage,
  authHeaders,
  isFormatUnavailable,
  isResponsesEndpointUnavailable,
  normalizeAuthMode,
  normalizeStructuredOutputMode,
  parseAndValidateStructuredText,
  readResponseData,
  requestChatStructured,
  responsesOutputText,
  responsesTextFormat,
  schemaInstructions,
} = require("./llm-compat.cjs");

let mainWindow;
let projectStore;

if (
  process.env.VITE_DEV_SERVER_URL &&
  /^\d{4,5}$/.test(process.env.SCRIPT_FORGE_CDP_PORT || "")
) {
  app.commandLine.appendSwitch(
    "remote-debugging-port",
    process.env.SCRIPT_FORGE_CDP_PORT,
  );
  app.commandLine.appendSwitch("remote-debugging-address", "127.0.0.1");
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1540,
    height: 960,
    minWidth: 1180,
    minHeight: 720,
    backgroundColor: "#f5f2eb",
    icon: path.join(__dirname, "../build/icon-aura.png"),
    title: "剧擎 ScriptForge",
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(__dirname, "preload.cjs"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });

  if (process.env.VITE_DEV_SERVER_URL) {
    mainWindow.loadURL(process.env.VITE_DEV_SERVER_URL);
  } else {
    mainWindow.loadFile(path.join(__dirname, "../dist/index.html"));
  }
}

function settingsPath() {
  return path.join(app.getPath("userData"), "model-settings.json");
}

const defaultSettings = {
  provider: "openai",
  protocol: "responses",
  authMode: "bearer",
  structuredOutput: "json_schema",
  baseUrl: "https://api.openai.com/v1",
  model: "gpt-5.6-terra",
  flashModel: "",
  imageModel: "",
  speechModel: "",
  speechVoice: "alloy",
  consentedEndpointHost: "",
  sendReasoning: true,
  reasoningEffort: "low",
  apiKeyEncrypted: "",
};

async function readSettingsRaw() {
  try {
    const raw = await fs.readFile(settingsPath(), "utf8");
    return { ...defaultSettings, ...JSON.parse(raw) };
  } catch {
    return { ...defaultSettings };
  }
}

function decryptApiKey(settings) {
  if (!settings.apiKeyEncrypted || !safeStorage.isEncryptionAvailable()) return "";
  try {
    return safeStorage.decryptString(Buffer.from(settings.apiKeyEncrypted, "base64"));
  } catch {
    return "";
  }
}

function publicSettings(settings) {
  const apiKey = decryptApiKey(settings);
  const { apiKeyEncrypted: _discarded, ...rest } = settings;
  return {
    ...rest,
    hasApiKey: Boolean(apiKey),
    hasFlashModel: Boolean(String(settings.flashModel || "").trim()),
    apiKeyHint: apiKey ? `•••• ${apiKey.slice(-4)}` : "",
  };
}

function confirmedBaseUrl(settings) {
  const baseUrl = normalizeApiRoot(settings.baseUrl);
  const host = new URL(baseUrl).host;
  if (host !== settings.consentedEndpointHost) {
    throw new Error(`Open Model & Preferences and confirm that selected project context may be sent to ${host}.`);
  }
  return baseUrl;
}

function modelForPayload(settings, payload) {
  if (payload.route === "flash") {
    const flashModel = String(settings.flashModel || "").trim();
    if (!flashModel) {
      throw new Error("Configure both the primary and fast model IDs.");
    }
    return flashModel;
  }
  return settings.model;
}

function requestHeaders(settings) {
  return authHeaders(settings.authMode, decryptApiKey(settings));
}

async function callResponsesApi(payload) {
  const settings = await readSettingsRaw();
  const model = modelForPayload(settings, payload);

  const baseUrl = confirmedBaseUrl(settings);
  const endpoint = appendApiPath(baseUrl, "responses");
  const headers = requestHeaders(settings);
  const outputMode = normalizeStructuredOutputMode(settings.structuredOutput);
  const textFormat = responsesTextFormat(outputMode, payload);
  const primaryBody = {
    model,
    instructions:
      outputMode === "json_schema"
        ? payload.instructions
        : schemaInstructions(payload),
    input: payload.input,
    store: false,
    ...(payload.route !== "flash" &&
    settings.sendReasoning !== false &&
    settings.reasoningEffort !== "none"
      ? { reasoning: { effort: settings.reasoningEffort || "low" } }
      : {}),
    ...(textFormat ? { text: { format: textFormat } } : {}),
  };
  let response = await fetch(endpoint, {
    method: "POST",
    headers,
    body: JSON.stringify(primaryBody),
  });
  let data = await readResponseData(response);

  if (!response.ok) {
    const message = apiErrorMessage(data, response.status);
    if (isResponsesEndpointUnavailable(message, response.status)) {
      return callChatApi(payload);
    }
    if (isFormatUnavailable(message)) {
      throw new Error(`${message}. This provider rejected JSON Schema output. The step was paused without an automatic paid retry.`);
    }
  }

  if (!response.ok) {
    throw new Error(apiErrorMessage(data, response.status));
  }
  return parseAndValidateStructuredText(
    responsesOutputText(data),
    payload.schema,
  );
}

async function callChatApi(payload) {
  const settings = await readSettingsRaw();
  const model = modelForPayload(settings, payload);

  const baseUrl = confirmedBaseUrl(settings);
  const endpoint = appendApiPath(baseUrl, "chat/completions");
  const headers = requestHeaders(settings);
  return requestChatStructured({
    fetchImpl: fetch,
    endpoint,
    headers,
    model,
    payload,
    structuredOutput: settings.structuredOutput,
  });
}

app.whenReady().then(() => {
  projectStore = new ProjectStore(path.join(app.getPath("userData"), "ScriptForgeData"));

  ipcMain.handle("file:open-document", async () => {
    const result = await dialog.showOpenDialog(mainWindow, {
      title: "Import a manuscript",
      properties: ["openFile"],
      filters: [
        { name: "Documents", extensions: SUPPORTED_EXTENSIONS },
        { name: "All files", extensions: ["*"] },
      ],
    });
    if (result.canceled || !result.filePaths[0]) return null;
    return readDocument(result.filePaths[0]);
  });

  ipcMain.handle("file:read-document", async (_event, filePath) => readDocument(filePath));

  ipcMain.handle("file:save-text", async (_event, payload) => {
    const extension = payload.extension === "md" ? "md" : "txt";
    const label = extension === "md" ? "Markdown document" : "UTF-8 text";
    const result = await dialog.showSaveDialog(mainWindow, {
      title: extension === "md" ? "Export book analysis" : "Export screenplay",
      defaultPath: `${String(payload.fileName || (extension === "md" ? "Book Analysis" : "Screenplay")).replace(/[\\/:*?"<>|]/g, "_")}.${extension}`,
      filters: [{ name: label, extensions: [extension] }],
    });
    if (result.canceled || !result.filePath) return null;
    await fs.writeFile(result.filePath, payload.content, "utf8");
    return result.filePath;
  });

  ipcMain.handle("file:save-export", async (_event, payload) => {
    const extension = ["md", "json", "docx", "txt"].includes(payload.extension)
      ? payload.extension
      : "md";
    const result = await dialog.showSaveDialog(mainWindow, {
      title: "Export from ScriptForge",
      defaultPath: `${String(payload.fileName || "ScriptForge Export").replace(/[\\/:*?"<>|]/g, "_")}.${extension}`,
      filters: [{ name: extension.toUpperCase(), extensions: [extension] }],
    });
    if (result.canceled || !result.filePath) return null;
    const content = extension === "docx"
      ? await makeDocx(payload.document)
      : String(payload.content || "");
    await fs.writeFile(result.filePath, content, extension === "docx" ? undefined : "utf8");
    return result.filePath;
  });

  ipcMain.handle("project:save", async (_event, project) => projectStore.saveProject(project));
  ipcMain.handle("project:load", async (_event, projectId) => projectStore.loadProject(projectId));
  ipcMain.handle("project:list", async () => projectStore.listProjects());
  ipcMain.handle("project:duplicate", async (_event, payload) => projectStore.duplicateProject(payload.sourceProjectId, payload.project));
  ipcMain.handle("project:delete", async (_event, projectId) => projectStore.deleteProject(projectId));
  ipcMain.handle("project:write-json", async (_event, payload) =>
    projectStore.writeJson(payload.projectId, payload.category, payload.itemId, payload.value));
  ipcMain.handle("project:read-json", async (_event, payload) =>
    projectStore.readJson(payload.projectId, payload.relativePath));
  ipcMain.handle("project:write-text", async (_event, payload) =>
    projectStore.writeText(payload.projectId, payload.category, payload.itemId, payload.content));
  ipcMain.handle("project:read-text", async (_event, payload) =>
    projectStore.readText(payload.projectId, payload.relativePath));

  ipcMain.handle("settings:get", async () => publicSettings(await readSettingsRaw()));

  ipcMain.handle("settings:update", async (_event, payload) => {
    const current = await readSettingsRaw();
    const normalizedBaseUrl = normalizeApiRoot(payload.baseUrl ?? current.baseUrl);
    const endpointHost = new URL(normalizedBaseUrl).host;
    if (endpointHost !== current.consentedEndpointHost && !payload.confirmEndpoint) {
      throw new Error(`Confirm that selected project context may be sent to ${endpointHost}.`);
    }
    const next = {
      ...current,
      provider: payload.provider ?? current.provider,
      protocol: payload.protocol ?? current.protocol,
      authMode: normalizeAuthMode(payload.authMode ?? current.authMode),
      structuredOutput: normalizeStructuredOutputMode(
        payload.structuredOutput ?? current.structuredOutput,
      ),
      baseUrl: normalizedBaseUrl,
      model: payload.model ?? current.model,
      flashModel: payload.flashModel ?? current.flashModel,
      imageModel: payload.imageModel ?? current.imageModel,
      speechModel: payload.speechModel ?? current.speechModel,
      speechVoice: payload.speechVoice ?? current.speechVoice,
      consentedEndpointHost: payload.confirmEndpoint
        ? endpointHost
        : current.consentedEndpointHost,
      sendReasoning: payload.sendReasoning ?? current.sendReasoning,
      reasoningEffort: payload.reasoningEffort ?? current.reasoningEffort,
    };
    if (payload.clearApiKey) next.apiKeyEncrypted = "";
    if (typeof payload.apiKey === "string" && payload.apiKey.trim()) {
      if (!safeStorage.isEncryptionAvailable()) {
        throw new Error("This system cannot securely encrypt the API key.");
      }
      next.apiKeyEncrypted = safeStorage
        .encryptString(payload.apiKey.trim())
        .toString("base64");
    }
    await fs.mkdir(path.dirname(settingsPath()), { recursive: true });
    await fs.writeFile(settingsPath(), JSON.stringify(next, null, 2), "utf8");
    return publicSettings(next);
  });

  ipcMain.handle("llm:structured", async (_event, payload) => {
    const settings = await readSettingsRaw();
    return settings.protocol === "chat"
      ? callChatApi(payload)
      : callResponsesApi(payload);
  });

  ipcMain.handle("media:image", async (_event, payload) => {
    const settings = await readSettingsRaw();
    if (!String(settings.imageModel || "").trim()) throw new Error("Configure an image model first.");
    const endpoint = appendApiPath(confirmedBaseUrl(settings), "images/generations");
    const response = await fetch(endpoint, { method: "POST", headers: requestHeaders(settings), body: JSON.stringify({ model: settings.imageModel, prompt: payload.prompt, size: "1024x1536", response_format: "b64_json" }) });
    const data = await readResponseData(response);
    if (!response.ok) throw new Error(apiErrorMessage(data, response.status));
    let content;
    if (data.data?.[0]?.b64_json) content = Buffer.from(data.data[0].b64_json, "base64");
    else if (data.data?.[0]?.url) {
      const mediaResponse = await fetch(data.data[0].url);
      if (!mediaResponse.ok) throw new Error("Unable to download the generated image.");
      content = Buffer.from(await mediaResponse.arrayBuffer());
    }
    if (!content?.length) throw new Error("The image model returned no image data.");
    return projectStore.writeBinary(payload.projectId, `media/${payload.episodeId}`, payload.shotId, "png", content);
  });

  ipcMain.handle("media:speech", async (_event, payload) => {
    const settings = await readSettingsRaw();
    if (!String(settings.speechModel || "").trim()) throw new Error("Configure a speech model first.");
    const endpoint = appendApiPath(confirmedBaseUrl(settings), "audio/speech");
    const response = await fetch(endpoint, { method: "POST", headers: requestHeaders(settings), body: JSON.stringify({ model: settings.speechModel, voice: settings.speechVoice || "alloy", input: payload.text, format: "mp3" }) });
    if (!response.ok) {
      const data = await readResponseData(response);
      throw new Error(apiErrorMessage(data, response.status));
    }
    const content = Buffer.from(await response.arrayBuffer());
    if (!content.length) throw new Error("The speech model returned no audio data.");
    return projectStore.writeBinary(payload.projectId, `media/${payload.episodeId}`, `${payload.shotId}-voice`, "mp3", content);
  });

  ipcMain.handle("media:read", async (_event, payload) => {
    const content = await projectStore.readBinary(payload.projectId, payload.relativePath);
    const extension = path.extname(payload.relativePath).toLowerCase();
    const mime = extension === ".mp3" ? "audio/mpeg" : extension === ".wav" ? "audio/wav" : "image/png";
    return `data:${mime};base64,${content.toString("base64")}`;
  });

  ipcMain.handle("app:version", () => app.getVersion());

  createWindow();

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit();
});

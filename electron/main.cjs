const { app, BrowserWindow, dialog, ipcMain, safeStorage } = require("electron");
const fs = require("node:fs/promises");
const path = require("node:path");
const {
  apiErrorMessage,
  isFormatUnavailable,
  isResponsesEndpointUnavailable,
  parseAndValidateStructuredText,
  requestChatStructured,
  responsesOutputText,
  schemaInstructions,
} = require("./llm-compat.cjs");

let mainWindow;

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
  baseUrl: "https://api.openai.com/v1",
  model: "gpt-5.6-terra",
  flashModel: "",
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

function modelForPayload(settings, payload) {
  if (payload.route === "flash") {
    const flashModel = String(settings.flashModel || "").trim();
    if (!flashModel) {
      throw new Error("双模型配置不完整");
    }
    return flashModel;
  }
  return settings.model;
}

async function callResponsesApi(payload) {
  const settings = await readSettingsRaw();
  const apiKey = decryptApiKey(settings);
  if (!apiKey) throw new Error("尚未配置模型 API Key");
  const model = modelForPayload(settings, payload);

  const baseUrl = settings.baseUrl.replace(/\/+$/, "");
  const endpoint = `${baseUrl}/responses`;
  const headers = {
    "Content-Type": "application/json",
    Authorization: `Bearer ${apiKey}`,
  };
  const primaryBody = {
    model,
    instructions: payload.instructions,
    input: payload.input,
    store: false,
    ...(payload.route === "flash"
      ? {}
      : { reasoning: { effort: settings.reasoningEffort || "low" } }),
    text: {
      format: {
        type: "json_schema",
        name: payload.name,
        strict: true,
        schema: payload.schema,
      },
    },
  };
  let response = await fetch(endpoint, {
    method: "POST",
    headers,
    body: JSON.stringify(primaryBody),
  });
  let data = await response.json().catch(() => ({}));

  if (!response.ok) {
    const message = apiErrorMessage(data, response.status);
    if (isResponsesEndpointUnavailable(message, response.status)) {
      return callChatApi(payload);
    }
    if (isFormatUnavailable(message)) {
      response = await fetch(endpoint, {
        method: "POST",
        headers,
        body: JSON.stringify({
          model,
          instructions: schemaInstructions(payload),
          input: payload.input,
          store: false,
          ...(payload.route === "flash"
            ? {}
            : { reasoning: { effort: settings.reasoningEffort || "low" } }),
        }),
      });
      data = await response.json().catch(() => ({}));
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
  const apiKey = decryptApiKey(settings);
  if (!apiKey) throw new Error("尚未配置模型 API Key");
  const model = modelForPayload(settings, payload);

  const baseUrl = settings.baseUrl.replace(/\/+$/, "");
  const endpoint = `${baseUrl}/chat/completions`;
  const headers = {
    "Content-Type": "application/json",
    Authorization: `Bearer ${apiKey}`,
  };
  return requestChatStructured({
    fetchImpl: fetch,
    endpoint,
    headers,
    model,
    payload,
  });
}

app.whenReady().then(() => {
  ipcMain.handle("file:open-text", async () => {
    const result = await dialog.showOpenDialog(mainWindow, {
      title: "导入小说文本",
      properties: ["openFile"],
      filters: [
        { name: "文本文件", extensions: ["txt", "md", "text"] },
        { name: "所有文件", extensions: ["*"] },
      ],
    });
    if (result.canceled || !result.filePaths[0]) return null;
    const filePath = result.filePaths[0];
    const text = await fs.readFile(filePath, "utf8");
    return { path: filePath, name: path.basename(filePath), text };
  });

  ipcMain.handle("file:save-text", async (_event, payload) => {
    const extension = payload.extension === "md" ? "md" : "txt";
    const label = extension === "md" ? "Markdown 文档" : "UTF-8 文本";
    const result = await dialog.showSaveDialog(mainWindow, {
      title: extension === "md" ? "导出拆书报告" : "导出短剧剧本",
      defaultPath: `${String(payload.fileName || (extension === "md" ? "拆书报告" : "短剧剧本")).replace(/[\\/:*?"<>|]/g, "_")}.${extension}`,
      filters: [{ name: label, extensions: [extension] }],
    });
    if (result.canceled || !result.filePath) return null;
    await fs.writeFile(result.filePath, payload.content, "utf8");
    return result.filePath;
  });

  ipcMain.handle("settings:get", async () => publicSettings(await readSettingsRaw()));

  ipcMain.handle("settings:update", async (_event, payload) => {
    const current = await readSettingsRaw();
    const next = {
      ...current,
      provider: payload.provider ?? current.provider,
      protocol: payload.protocol ?? current.protocol,
      baseUrl: payload.baseUrl ?? current.baseUrl,
      model: payload.model ?? current.model,
      flashModel: payload.flashModel ?? current.flashModel,
      reasoningEffort: payload.reasoningEffort ?? current.reasoningEffort,
    };
    if (payload.clearApiKey) next.apiKeyEncrypted = "";
    if (typeof payload.apiKey === "string" && payload.apiKey.trim()) {
      if (!safeStorage.isEncryptionAvailable()) {
        throw new Error("当前系统无法安全加密 API Key");
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

  ipcMain.handle("app:version", () => app.getVersion());

  createWindow();

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit();
});

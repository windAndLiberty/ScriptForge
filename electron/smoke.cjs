const { app, BrowserWindow } = require("electron");
const fsSync = require("node:fs");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");

app.commandLine.appendSwitch("disable-gpu");

const smokeUserDataDir = fsSync.mkdtempSync(
  path.join(os.tmpdir(), "scriptforge-smoke-"),
);
app.setPath("userData", smokeUserDataDir);

const fixtureProject = {
  schemaVersion: 5,
  id: "visual-smoke",
  qualityProfileVersion: 2,
  name: "开局地摊卖大力·短剧改编",
  document: {
    fileName: "开局地摊卖大力_1-10.txt",
    title: "开局地摊卖大力",
    author: "弈青锋",
    intro: "地球进入灵气复苏时代，少年意外获得地摊系统。",
    rawText: "系统 异能 觉醒",
    charCount: 23173,
    chapters: [
      "我秃了！也变强了？",
      "根本停不下来",
      "就问你医院WIFI快不快？",
      "是你么？琦玉老师",
      "被打一拳就觉醒了？",
      "绝活！脑门碎大石",
      "两面夹击！",
      "我一定是被金钱蒙蔽了双眼",
      "你这个小数点很不懂事啊",
      "去给他点颜色看看",
    ].map((title, index) => ({
      id: `chapter-${index + 1}`,
      index: index + 1,
      title,
      content:
        "夜市人声鼎沸。主角守着摊位，没想到一次公开冲突让命运突然转向。围观人群齐齐回头，更大的麻烦正在靠近。",
      charCount: 2200 + index * 27,
    })),
  },
  characters: [
    ["江南", "程野", 257, "核心主角"],
    ["夏瑶", "沈知夏", 61, "主要角色"],
    ["钟映雪", "林妍", 45, "主要角色"],
    ["王林", "周骁", 33, "关键配角"],
    ["李慕言", "苏清禾", 30, "关键配角"],
    ["郑伟", "顾川", 27, "关键配角"],
    ["李响", "陆沉舟", 17, "关键配角"],
    ["周雨晴", "许昭月", 10, "关键配角"],
  ].map(([sourceName, targetName, occurrences, role], index) => ({
    id: `character-${index + 1}`,
    sourceName,
    targetName,
    occurrences,
    role,
    traits: ["强动机", "关系驱动"],
    locked: true,
  })),
  options: {
    episodeCount: 8,
    durationSeconds: 60,
    scenesPerEpisode: 3,
    genre: "都市逆袭·热血轻喜",
    tone: "高燃、机敏、轻喜",
    trendPreset: "精品爽剧",
  },
  result: null,
  creativeWorkspace: {
    projectInstruction: "",
    briefs: [], storyBibles: [], outlines: [], chapters: [], characterStates: [], timeline: [], foreshadowing: [], continuityIssues: [], runs: [], artifacts: [], promptOverrides: [], handoffs: [],
  },
  phase: "characters",
  updatedAt: new Date().toISOString(),
};

async function capture(window, fileName) {
  await window.webContents.executeJavaScript(`Promise.race([
    new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))),
    new Promise((resolve) => setTimeout(resolve, 1000)),
  ])`);
  await new Promise((resolve) => setTimeout(resolve, 700));
  let image;
  let lastError;
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    try {
      image = await window.webContents.capturePage();
      break;
    } catch (error) {
      lastError = error;
      if (attempt < 3) {
        await new Promise((resolve) => setTimeout(resolve, 500));
      }
    }
  }
  if (!image) {
    throw new Error(
      `Unable to capture ${fileName} after three attempts: ${lastError instanceof Error ? lastError.message : String(lastError)}`,
    );
  }
  const outputDir = path.join(__dirname, "../acceptance");
  await fs.mkdir(outputDir, { recursive: true });
  await fs.writeFile(path.join(outputDir, fileName), image.toPNG());
}

function reloadWindow(window) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      cleanup();
      reject(new Error("Timed out waiting for the smoke window to reload."));
    }, 15_000);
    const cleanup = () => {
      clearTimeout(timeout);
      window.webContents.removeListener("did-finish-load", onFinish);
      window.webContents.removeListener("did-fail-load", onFail);
    };
    const onFinish = () => {
      cleanup();
      resolve();
    };
    const onFail = (_event, code, description, url, isMainFrame) => {
      if (!isMainFrame) return;
      cleanup();
      reject(new Error(`Smoke window reload failed (${code}) at ${url}: ${description}`));
    };
    window.webContents.on("did-finish-load", onFinish);
    window.webContents.on("did-fail-load", onFail);
    window.reload();
  });
}

app.whenReady().then(async () => {
  const window = new BrowserWindow({
    width: 1440,
    height: 900,
    // A hidden BrowserWindow can stop compositing after in-page navigation on
    // Windows, causing capturePage() to save the previous view. Keep the smoke
    // window visible so every acceptance screenshot reflects the asserted page.
    show: true,
    backgroundColor: "#efede7",
    webPreferences: {
      backgroundThrottling: false,
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });
  const entry = path.join(__dirname, "../dist/index.html");
  await window.loadFile(entry);
  await capture(window, "ui-empty.png");
  await window.webContents.executeJavaScript(
    `localStorage.setItem("scriptforge.project.v1", ${JSON.stringify(
      JSON.stringify(fixtureProject),
    )})`,
  );
  await reloadWindow(window);
  await capture(window, "ui-workbench.png");
  await window.webContents.executeJavaScript(
    'localStorage.setItem("scriptforge.locale.v1", "en-US")',
  );
  await reloadWindow(window);
  await capture(window, "ui-workbench-en.png");
  const settingsCompatibilityChecked = await window.webContents.executeJavaScript(`(async () => {
    const button = [...document.querySelectorAll(".sidebar-bottom button")].find((item) =>
      item.textContent.includes("Model & Preferences")
    );
    button?.click();
    await new Promise((resolve) => requestAnimationFrame(resolve));
    const dialog = document.querySelector(".settings-dialog");
    const auth = dialog?.querySelector('select option[value="x-goog-api-key"]');
    const local = dialog?.querySelector('select option[value="none"]');
    const promptOnly = dialog?.querySelector('select option[value="prompt_only"]');
    return Boolean(
      button &&
      dialog &&
      dialog.textContent.includes("Structured Output") &&
      auth &&
      local &&
      promptOnly
    );
  })()`);
  if (!settingsCompatibilityChecked) {
    throw new Error("Model compatibility settings smoke check failed");
  }
  await capture(window, "ui-model-compatibility-en.png");
  await window.webContents.executeJavaScript(
    `document.querySelector(".settings-dialog .dialog-heading .icon-button")?.click()`,
  );
  const authorOpened = await window.webContents.executeJavaScript(`(async () => {
    const item = [...document.querySelectorAll(".nav-item")].find((button) =>
      button.textContent.includes("Author Studio")
    );
    item?.click();
    await new Promise((resolve) => requestAnimationFrame(resolve));
    return Boolean(item && document.querySelector(".author-studio"));
  })()`);
  if (!authorOpened) throw new Error("Author Studio navigation smoke check failed");
  await capture(window, "ui-author-studio-en.png");
  const lightThemeApplied = await window.webContents.executeJavaScript(`(async () => {
    const toggle = document.querySelector('.accessibility-controls button[title="Switch theme"]');
    toggle?.click();
    await new Promise((resolve) => requestAnimationFrame(resolve));
    return Boolean(toggle && document.documentElement.dataset.theme === "light");
  })()`);
  if (!lightThemeApplied) throw new Error("Light theme smoke check failed");
  await capture(window, "ui-author-studio-light-en.png");
  await window.webContents.executeJavaScript(`document.querySelector('.accessibility-controls button[title="Switch theme"]')?.click()`);
  const bookOpened = await window.webContents.executeJavaScript(`(async () => {
    const item = [...document.querySelectorAll(".nav-item")].find((button) =>
      button.textContent.includes("One-click Book Analysis")
    );
    item?.click();
    await new Promise((resolve) => requestAnimationFrame(resolve));
    return Boolean(item && document.querySelector(".book-analysis-workspace"));
  })()`);
  if (!bookOpened) throw new Error("Book Analysis navigation smoke check failed");
  await capture(window, "ui-book-analysis-en.png");
  const projectsOpened = await window.webContents.executeJavaScript(`(async () => {
    const item = [...document.querySelectorAll(".nav-item")].find((button) =>
      button.textContent.includes("Projects")
    );
    item?.click();
    await new Promise((resolve) => requestAnimationFrame(resolve));
    return Boolean(item && document.querySelector(".library-workspace"));
  })()`);
  if (!projectsOpened) throw new Error("Projects navigation smoke check failed");
  await capture(window, "ui-projects-en.png");
  const promptsOpened = await window.webContents.executeJavaScript(`(async () => {
    const item = [...document.querySelectorAll(".nav-item")].find((button) =>
      button.textContent.includes("Prompt Assets")
    );
    item?.click();
    await new Promise((resolve) => requestAnimationFrame(resolve));
    return Boolean(item && document.querySelector(".prompt-workspace"));
  })()`);
  if (!promptsOpened) throw new Error("Prompt Assets navigation smoke check failed");
  await capture(window, "ui-prompts-en.png");
  const resetOpenedHome = await window.webContents.executeJavaScript(`(async () => {
    const studio = [...document.querySelectorAll(".nav-item")].find((button) =>
      button.textContent.includes("Adaptation Studio")
    );
    studio?.click();
    await new Promise((resolve) => requestAnimationFrame(resolve));
    const reset = [...document.querySelectorAll(".top-actions button")].find((button) =>
      button.textContent.includes("Reset Home")
    );
    reset?.click();
    await new Promise((resolve) => setTimeout(resolve, 350));
    const saved = JSON.parse(localStorage.getItem("scriptforge.project.v1") || "{}");
    return Boolean(
      studio &&
      reset &&
      document.querySelector(".empty-workspace") &&
      !saved.document
    );
  })()`);
  if (!resetOpenedHome) throw new Error("Reset Home smoke check failed");
  await capture(window, "ui-reset-home-en.png");
  window.destroy();
  await fs.rm(smokeUserDataDir, { recursive: true, force: true });
  app.quit();
}).catch(async (error) => {
  console.error(error);
  for (const window of BrowserWindow.getAllWindows()) window.destroy();
  await fs.rm(smokeUserDataDir, { recursive: true, force: true }).catch(() => {});
  app.exit(1);
});

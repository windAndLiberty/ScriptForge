const assert = require("node:assert/strict");

const endpoint = process.env.SCRIPT_FORGE_CDP_URL || "http://127.0.0.1:9421";

async function connect() {
  const targets = await fetch(`${endpoint}/json/list`).then((response) =>
    response.json(),
  );
  const page = targets.find(
    (target) =>
      target.type === "page" && target.url.startsWith("http://127.0.0.1:5417"),
  );
  assert(page, "未找到 ScriptForge 开发版页面");

  const socket = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    socket.addEventListener("open", resolve, { once: true });
    socket.addEventListener("error", reject, { once: true });
  });

  let sequence = 0;
  const pending = new Map();
  const exceptions = [];
  socket.addEventListener("message", (event) => {
    const message = JSON.parse(event.data);
    if (message.id && pending.has(message.id)) {
      const { resolve, reject } = pending.get(message.id);
      pending.delete(message.id);
      if (message.error) reject(new Error(message.error.message));
      else resolve(message.result);
    }
    if (message.method === "Runtime.exceptionThrown") {
      exceptions.push(
        message.params?.exceptionDetails?.exception?.description ||
          message.params?.exceptionDetails?.text ||
          "Unknown renderer exception",
      );
    }
  });

  const send = (method, params = {}) =>
    new Promise((resolve, reject) => {
      const id = ++sequence;
      pending.set(id, { resolve, reject });
      socket.send(JSON.stringify({ id, method, params }));
    });
  const evaluate = async (expression, awaitPromise = true) => {
    const response = await send("Runtime.evaluate", {
      expression,
      awaitPromise,
      returnByValue: true,
    });
    if (response.exceptionDetails) {
      throw new Error(
        response.exceptionDetails.exception?.description ||
          response.exceptionDetails.text,
      );
    }
    return response.result?.value;
  };
  await send("Runtime.enable");
  return { socket, evaluate, exceptions };
}

async function main() {
  const { socket, evaluate, exceptions } = await connect();
  const initial = await evaluate(`(() => {
    const project = JSON.parse(localStorage.getItem("scriptforge.project.v1") || "null");
    const episodes = project?.result?.episodes;
    const readableLength = (value) =>
      String(value || "").match(/[\\p{L}\\p{N}]/gu)?.length || 0;
    return {
      title: document.title,
      rootChildren: document.querySelector("#root")?.childElementCount || 0,
      visibleError: document.querySelector(".error-toast")?.textContent || "",
      hasResetButton: [...document.querySelectorAll(".top-actions button")]
        .some((button) => /重置首页|Reset Home/.test(button.textContent || "")),
      resultShapeSafe: !episodes || (
        Array.isArray(episodes) &&
        episodes.every((episode) =>
          Array.isArray(episode.scenes) &&
          episode.scenes.every((scene) => Array.isArray(scene.dialogue))
        )
      ),
      qualitySummary: project?.result
        ? {
            phase: project.phase,
            score: project.result.quality?.score,
            passed: project.result.quality?.passed,
            metrics: (project.result.quality?.metrics || []).map((metric) => ({
              id: metric.id,
              score: metric.score,
              detail: metric.detail,
            })),
            episodes: (episodes || []).map((episode) => ({
              number: episode.number,
              plannedScenes: episode.plannedSceneCount,
              scenes: episode.scenes.length,
              dialogueLines: episode.scenes.reduce(
                (total, scene) => total + scene.dialogue.length,
                0,
              ),
              spokenCharacters: episode.scenes.reduce(
                (total, scene) =>
                  total +
                  scene.dialogue.reduce(
                    (lineTotal, line) =>
                      lineTotal + readableLength(line.text),
                    0,
                  ),
                0,
              ),
              actionCharacters: episode.scenes.reduce(
                (total, scene) =>
                  total +
                  readableLength(scene.action) +
                  readableLength(scene.heading) +
                  readableLength(scene.location),
                0,
              ),
              speakers: [
                ...new Set(
                  episode.scenes.flatMap((scene) =>
                    scene.dialogue.map((line) => line.speaker),
                  ),
                ),
              ].length,
            })),
          }
        : null,
    };
  })()`, false);
  assert.equal(initial.title, "剧擎 ScriptForge");
  assert(initial.rootChildren > 0, "React 根节点为空");
  assert(!initial.visibleError.includes("Cannot read properties"), initial.visibleError);
  assert(initial.hasResetButton, "未找到重置首页按钮");
  assert(initial.resultShapeSafe, "当前本地项目尚未迁移为安全结构");
  if (process.env.SCRIPT_FORGE_QUALITY_ONLY === "1") {
    socket.close();
    console.log(JSON.stringify(initial.qualitySummary, null, 2));
    return;
  }

  const routes = [
    ["一键拆书", "One-click Book Analysis", ".book-analysis-workspace"],
    ["项目档案", "Projects", ".library-workspace"],
    ["提示词资产", "Prompt Assets", ".prompt-workspace"],
    ["改编工坊", "Adaptation Studio", ".empty-workspace, .workspace-grid"],
  ];
  let biblePromptAssetFound = false;
  let projectArchiveUi = null;
  let bookAnalysisUi = null;
  for (const [chinese, english, selector] of routes) {
    const opened = await evaluate(`(async () => {
      const button = [...document.querySelectorAll(".nav-item")].find((item) =>
        (item.textContent || "").includes(${JSON.stringify(chinese)}) ||
        (item.textContent || "").includes(${JSON.stringify(english)})
      );
      button?.click();
      await new Promise((resolve) => setTimeout(resolve, 100));
      return Boolean(button && document.querySelector(${JSON.stringify(selector)}));
    })()`);
    assert(opened, `${chinese} 导航失败`);
    if (chinese === "一键拆书") {
      bookAnalysisUi = await evaluate(`(() => {
        const navItems = [...document.querySelectorAll(".primary-nav .nav-item")];
        const bookIndex = navItems.findIndex((item) =>
          /一键拆书|One-click Book Analysis/.test(item.textContent || "")
        );
        const studioIndex = navItems.findIndex((item) =>
          /改编工坊|Adaptation Studio/.test(item.textContent || "")
        );
        const workspace = document.querySelector(".book-analysis-workspace");
        const action = [...(workspace?.querySelectorAll("button") || [])].find((item) =>
          /开始一键拆书|重新一键拆书|导入小说并开始|Start One-click Analysis|Run Again|Import Novel and Start/.test(item.textContent || "")
        );
        return {
          hasWorkspace: Boolean(workspace),
          hasPrimaryAction: Boolean(action),
          aboveStudio: bookIndex >= 0 && studioIndex === bookIndex + 1,
        };
      })()`, false);
    }
    if (chinese === "项目档案") {
      projectArchiveUi = await evaluate(`(async () => {
        const cards = [...document.querySelectorAll(".archive-card")];
        const summarySwitches = [...document.querySelectorAll(".library-summary-switch")];
        const filters = summarySwitches.map((item) => item.textContent || "");
        const archivedFilter = summarySwitches.find((item) =>
          /已归档|Archived/.test(item.textContent || "")
        );
        archivedFilter?.click();
        await new Promise((resolve) => setTimeout(resolve, 100));
        const archivedCardCount =
          document.querySelectorAll(".archive-card.archived").length;
        const deleteActions =
          document.querySelectorAll(".archive-delete-action").length;
        return {
          cardCount: cards.length,
          clickableCards: cards.filter((card) =>
            card.getAttribute("role") === "button" &&
            card.getAttribute("tabindex") === "0"
          ).length,
          hasRecentFilter: filters.some((text) =>
            /最近项目|Recent Projects/.test(text)
          ),
          hasArchivedFilter: filters.some((text) =>
            /已归档|Archived/.test(text)
          ),
          legacyFilterRemoved: !document.querySelector(".library-filter"),
          staticSummaryCount:
            document.querySelectorAll(".library-summary-static").length,
          staticSummaryButtons: [...document.querySelectorAll(".library-summary-static")]
            .filter((item) => item.matches("button") || item.getAttribute("role") === "button")
            .length,
          archiveActions: document.querySelectorAll(".archive-action").length,
          archivedCardCount,
          deleteActions,
        };
      })()`);
    }
    if (chinese === "提示词资产") {
      const promptAssetInspection = await evaluate(`(() => {
        const items = [...document.querySelectorAll(".prompt-list button, .prompt-rail button")];
        return {
          bibleFound: items.some((item) =>
            /全剧事实圣经|Series Source of Truth/.test(item.textContent || "")
          ),
          count: items.length,
          impactHints: items.filter((item) =>
            Boolean(item.getAttribute("data-impact")?.trim())
          ).length,
        };
      })()`, false);
      biblePromptAssetFound = promptAssetInspection.bibleFound;
      assert.equal(
        promptAssetInspection.impactHints,
        promptAssetInspection.count,
        "提示词资产缺少影响范围悬停提示",
      );
    }
  }

  const automation = await evaluate(`(() => {
    const hasImportedProject = Boolean(document.querySelector(".workspace-grid"));
    const sceneItem = [...document.querySelectorAll(".brief-grid > *")]
      .some((item) =>
        /每集场次|Scenes per Episode/.test(item.textContent || "")
      );
    const characterNames = [...document.querySelectorAll(".target-name input")]
      .map((element) => element.value || "");
    return {
      hasImportedProject,
      perEpisodeSceneItemRemoved: !sceneItem,
      placeholderCharacterNameVisible: characterNames.some((name) =>
        /^(?:角色|人物|Character)\\s*\\d+$/i.test(name.trim())
      ),
      editableCharacterNamesAvailable: !hasImportedProject ||
        document.querySelectorAll(".character-row .target-name input").length > 0,
      seriesBibleTabAvailable: [...document.querySelectorAll(".tabs button")]
        .some((button) =>
          /全剧圣经|Series Bible/.test(button.textContent || "")
        ),
    };
  })()`);
  assert(automation.perEpisodeSceneItemRemoved, "仍存在每集场次规格项");
  assert(
    !automation.placeholderCharacterNameVisible,
    "角色面板仍显示数字占位名",
  );
  assert(
    automation.editableCharacterNamesAvailable,
    "角色面板没有提供手动改名输入框",
  );
  assert(automation.seriesBibleTabAvailable, "缺少全剧圣经结果页");
  assert(biblePromptAssetFound, "缺少全剧事实圣经提示词资产");
  assert(bookAnalysisUi?.hasWorkspace, "缺少一键拆书工作区");
  assert(bookAnalysisUi?.hasPrimaryAction, "一键拆书缺少主要操作按钮");
  assert(bookAnalysisUi?.aboveStudio, "一键拆书入口未位于改编工坊上方");
  assert(projectArchiveUi?.hasRecentFilter, "缺少最近项目筛选");
  assert(projectArchiveUi?.hasArchivedFilter, "缺少已归档筛选");
  assert(projectArchiveUi?.legacyFilterRemoved, "仍存在重复的项目筛选按钮");
  assert.equal(
    projectArchiveUi?.staticSummaryCount,
    2,
    "累计章节和已生成集数统计卡结构异常",
  );
  assert.equal(
    projectArchiveUi?.staticSummaryButtons,
    0,
    "累计章节和已生成集数不应可点击",
  );
  assert.equal(
    projectArchiveUi?.clickableCards,
    projectArchiveUi?.cardCount,
    "项目卡片未全部支持整卡点击",
  );
  assert.equal(
    projectArchiveUi?.deleteActions,
    projectArchiveUi?.archivedCardCount,
    "归档项目未全部提供删除操作",
  );

  const dualModelSettings = await evaluate(`(async () => {
    const button = [...document.querySelectorAll(".sidebar-bottom button")]
      .find((item) => /模型与偏好|Model & Preferences/.test(item.textContent || ""));
    button?.click();
    await new Promise((resolve) => setTimeout(resolve, 100));
    const labels = [...document.querySelectorAll(".settings-grid label")]
      .map((label) => label.textContent || "");
    const result = {
      primaryModelField: labels.some((label) =>
        /创作模型|Creative Model/.test(label)
      ),
      flashModelField: labels.some((label) =>
        /高速模型|Fast Model/.test(label)
      ),
      stageRoutingControlsAbsent: !labels.some((label) =>
        /审片模型|修复模型|Audit Model|Repair Model|管线路由|Pipeline Routing/.test(label)
      ),
    };
    document.querySelector(".dialog-heading .icon-button")?.click();
    return result;
  })()`);
  assert(dualModelSettings.primaryModelField, "缺少创作模型配置");
  assert(dualModelSettings.flashModelField, "缺少高速模型配置");
  assert(
    dualModelSettings.stageRoutingControlsAbsent,
    "不应向用户暴露内部管线路由",
  );

  await new Promise((resolve) => setTimeout(resolve, 150));
  assert.equal(exceptions.length, 0, exceptions.join("\n"));
  socket.close();
  console.log(
    JSON.stringify(
      {
        status: "PASS",
        developmentUrl: "http://127.0.0.1:5417/",
        initial,
        automation,
        biblePromptAssetFound,
        projectArchiveUi,
        dualModelSettings,
        checkedRoutes: routes.map(([name]) => name),
        rendererExceptions: exceptions,
      },
      null,
      2,
    ),
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

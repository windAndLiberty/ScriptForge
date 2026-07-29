import {
  Archive,
  ArchiveRestore,
  BookOpen,
  Bot,
  Check,
  CheckCircle2,
  ChevronDown,
  CircleGauge,
  Clapperboard,
  Cloud,
  Copy,
  Download,
  FilePlus2,
  FileText,
  FolderKanban,
  History,
  Import,
  KeyRound,
  Library,
  Languages,
  MoreHorizontal,
  PenLine,
  Play,
  RefreshCw,
  RotateCcw,
  Save,
  Search,
  Settings,
  ShieldCheck,
  Sparkles,
  Trash2,
  UploadCloud,
  UserRound,
  UsersRound,
  WandSparkles,
  X,
} from "lucide-react";
import {
  useEffect,
  useMemo,
  useRef,
  useState,
  type ChangeEvent,
  type DragEvent,
  type ReactNode,
} from "react";
import type {
  AdaptationOptions,
  AdaptationResult,
  BookAnalysisResult,
  CharacterProfile,
  PipelinePhase,
  StoredProject,
} from "./domain";
import {
  assertValidRenameMap,
  extractCharacters,
  resolveModelCharacterNames,
} from "./pipeline/characters";
import { parseNovelText } from "./pipeline/ingest";
import { buildOfflineAdaptation } from "./pipeline/offline";
import {
  generateModelCharacterNames,
  runOnlinePipeline,
} from "./pipeline/online";
import {
  sanitizeAdaptationResult,
  sanitizeCharacters,
  sanitizeDocument,
} from "./pipeline/projectMigration";
import {
  recommendedEpisodeCount,
  recommendedScenes,
  runtimeBudget,
} from "./pipeline/episodeBudget";
import { useI18n, type Translate } from "./i18n";
import {
  DEFAULT_PROMPT_ASSETS,
  loadPromptAssets,
  type PromptAsset,
} from "./promptAssets";
import {
  archiveProject as archiveProjectInLibrary,
  deleteArchivedProject as deleteArchivedProjectInLibrary,
  enforceRecentProjectLimit,
  restoreProject as restoreProjectInLibrary,
  upsertProject,
} from "./pipeline/projectArchive";
import {
  buildOfflineBookAnalysis,
  renderBookAnalysisMarkdown,
  reviseBookAnalysis,
  runOnlineBookAnalysis,
  sanitizeBookAnalysisResult,
  selectBookAnalysisVersion,
  type BookAnalysisProgress,
} from "./pipeline/bookAnalysis";

type PrimaryView = "book" | "studio" | "projects" | "prompts";

const DEFAULT_OPTIONS: AdaptationOptions = {
  episodeCount: 8,
  durationSeconds: 90,
  scenesPerEpisode: 4,
  genre: "都市逆袭·热血轻喜",
  tone: "高燃、机敏、轻喜",
  trendPreset: "精品爽剧",
};
const PHASES: Array<{ id: PipelinePhase; label: string }> = [
  { id: "ingest", label: "文本拆解" },
  { id: "analysis", label: "故事事实" },
  { id: "characters", label: "人物改名" },
  { id: "bible", label: "全剧圣经" },
  { id: "outline", label: "分集规划" },
  { id: "drafting", label: "逐集成稿" },
  { id: "quality", label: "质量校验" },
];
const PHASE_ORDER: PipelinePhase[] = [
  "idle",
  "ingest",
  "analysis",
  "characters",
  "bible",
  "outline",
  "drafting",
  "quality",
  "completed",
];

function createProject(): StoredProject {
  const locale = localStorage.getItem("scriptforge.locale.v1");
  return {
    id: crypto.randomUUID(),
    qualityProfileVersion: 6,
    name: locale === "en-US" ? "New Adaptation Project" : "新建改编项目",
    document: null,
    characters: [],
    options: DEFAULT_OPTIONS,
    result: null,
    bookAnalysis: null,
    phase: "idle",
    updatedAt: new Date().toISOString(),
  };
}

function normalizeStoredProject(value: StoredProject): StoredProject {
  const previousVersion = value?.qualityProfileVersion || 1;
  const options = {
    ...DEFAULT_OPTIONS,
    ...(value?.options || {}),
    scenesPerEpisode:
      previousVersion < 3
        ? recommendedScenes(value?.options?.durationSeconds || 90)
        : value?.options?.scenesPerEpisode || DEFAULT_OPTIONS.scenesPerEpisode,
  };
  const characters = sanitizeCharacters(value?.characters);
  const document = sanitizeDocument(value?.document);
  const normalized: StoredProject = {
    ...createProject(),
    ...(value || {}),
    qualityProfileVersion: 6,
    document,
    characters,
    options,
    result: null,
    bookAnalysis: sanitizeBookAnalysisResult(value?.bookAnalysis),
  };
  normalized.result = sanitizeAdaptationResult(
    value?.result,
    normalized.options,
    normalized.characters,
  );
  if (value?.result && !normalized.result) {
    normalized.phase = document ? "characters" : "idle";
  } else if (normalized.result) {
    if (!normalized.result.quality.passed) {
      normalized.phase = "quality";
    }
  }
  return normalized;
}

function loadProject(): StoredProject {
  try {
    const saved = localStorage.getItem("scriptforge.project.v1");
    return saved
      ? normalizeStoredProject(JSON.parse(saved) as StoredProject)
      : createProject();
  } catch {
    return createProject();
  }
}

function loadProjectLibrary(): StoredProject[] {
  try {
    const saved = JSON.parse(
      localStorage.getItem("scriptforge.projects.v1") || "[]",
    );
    if (!Array.isArray(saved)) return [];
    const normalized = enforceRecentProjectLimit(
      saved.map((item) => normalizeStoredProject(item as StoredProject)),
    );
    localStorage.setItem(
      "scriptforge.projects.v1",
      JSON.stringify(normalized),
    );
    return normalized;
  } catch {
    return [];
  }
}

function persistProjectLibrary(projects: StoredProject[]) {
  localStorage.setItem("scriptforge.projects.v1", JSON.stringify(projects));
  return projects;
}

function cleanAppError(caught: unknown, fallback: string) {
  const message = caught instanceof Error ? caught.message : fallback;
  return message
    .replace(/^Error invoking remote method '[^']+':\s*/i, "")
    .replace(/^Error:\s*/i, "");
}

function formatNumber(value: number) {
  return new Intl.NumberFormat("zh-CN").format(value);
}

function wait(ms: number) {
  return new Promise((resolve) => window.setTimeout(resolve, ms));
}

function projectExport(
  result: AdaptationResult,
  project: StoredProject,
  t: Translate,
) {
  return [
    `《${project.name}》`,
    `${t("题材")}：${result.genre}`,
    `${t("规格")}：${result.episodes.length} ${t("集")} × ${t("约")} ${t("{{seconds}} 秒", { seconds: project.options.durationSeconds })}`,
    `${t("一句话梗概")}：${result.logline}`,
    `${t("生成方式")}：${t(result.mode === "online" ? "结构化大模型管线" : "离线验收管线")}`,
    t("提示：AI辅助内容，须经编剧、制片与合规人员复核。"),
    "",
    ...result.episodes.flatMap((episode) => [episode.content, "", ""]),
  ].join("\n");
}

export default function App() {
  const { locale, setLocale, t } = useI18n();
  const [project, setProject] = useState<StoredProject>(loadProject);
  const [projectLibrary, setProjectLibrary] =
    useState<StoredProject[]>(loadProjectLibrary);
  const [promptAssets, setPromptAssets] =
    useState<PromptAsset[]>(loadPromptAssets);
  const [primaryView, setPrimaryView] = useState<PrimaryView>("studio");
  const [selectedChapter, setSelectedChapter] = useState(0);
  const [selectedEpisode, setSelectedEpisode] = useState(0);
  const [activeTab, setActiveTab] = useState<
    "outline" | "bible" | "script" | "quality"
  >("outline");
  const [progress, setProgress] = useState(0);
  const [progressDetail, setProgressDetail] = useState("");
  const [toast, setToast] = useState("");
  const [error, setError] = useState("");
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [pendingDelete, setPendingDelete] = useState<StoredProject | null>(null);
  const [settings, setSettings] = useState<ModelSettings | null>(null);
  const [useOnline, setUseOnline] = useState(false);
  const [running, setRunning] = useState(false);
  const [bookRunning, setBookRunning] = useState(false);
  const [bookRevising, setBookRevising] = useState(false);
  const [bookProgress, setBookProgress] = useState<BookAnalysisProgress>({
    stage: "preparing",
    completed: 0,
    total: 0,
    percent: 0,
    message: "",
  });
  const fileInput = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const handle = window.setTimeout(() => {
      const snapshot = { ...project, updatedAt: new Date().toISOString() };
      localStorage.setItem("scriptforge.project.v1", JSON.stringify(snapshot));
      setProjectLibrary((current) => {
        return persistProjectLibrary(upsertProject(current, snapshot));
      });
    }, 250);
    return () => window.clearTimeout(handle);
  }, [project]);

  useEffect(() => {
    const handle = window.setTimeout(() => {
      localStorage.setItem(
        "scriptforge.prompt-assets.v1",
        JSON.stringify(promptAssets),
      );
    }, 200);
    return () => window.clearTimeout(handle);
  }, [promptAssets]);

  useEffect(() => {
    window.desktopAPI?.getSettings().then((value) => {
      setSettings(value);
      setUseOnline(value.hasApiKey && value.hasFlashModel);
    });
  }, []);

  useEffect(() => {
    if (!toast) return;
    const handle = window.setTimeout(() => setToast(""), 2600);
    return () => window.clearTimeout(handle);
  }, [toast]);

  const currentPhaseIndex = PHASE_ORDER.indexOf(project.phase);
  const recentProjectCount =
    projectLibrary.filter((item) => !item.archivedAt).length +
    (projectLibrary.some((item) => item.id === project.id) ||
    project.archivedAt
      ? 0
      : 1);
  const selectedChapterData = project.document?.chapters[selectedChapter];
  const selectedEpisodeData = project.result?.episodes[selectedEpisode];

  const runAutomaticNaming = async (
    document: NonNullable<StoredProject["document"]>,
    characters: CharacterProfile[],
    options: AdaptationOptions,
    connection = settings,
  ) => {
    if (
      !window.desktopAPI ||
      !connection?.hasApiKey ||
      !connection.hasFlashModel ||
      !characters.some(
        (character) =>
          !["model", "manual"].includes(character.nameSource || "") ||
          !character.targetName.trim(),
      )
    ) {
      return;
    }
    setProgressDetail(t("正在自动整理角色名称"));
    try {
      const namedCharacters = await generateModelCharacterNames({
        document,
        characters,
        options,
        promptAssets,
        callStructured: (payload) =>
          window.desktopAPI!.callStructured(payload),
      });
      const generatedById = new Map(
        namedCharacters.map((character) => [character.id, character]),
      );
      setProject((current) => {
        if (current.document?.rawText !== document.rawText) return current;
        return {
          ...current,
          characters: current.characters.map((character) =>
            character.nameSource === "manual"
              ? character
              : generatedById.get(character.id) || character,
          ),
        };
      });
      setProgressDetail(t("角色名称已生成，可继续手动修改"));
      setToast(t("角色名称已自动生成"));
    } catch (caught) {
      setError(cleanAppError(caught, t("角色自动命名失败")));
    }
  };

  const importText = (text: string, fileName: string) => {
    try {
      setError("");
      const document = parseNovelText(text, fileName);
      const characters = extractCharacters(document);
      const options = {
        ...DEFAULT_OPTIONS,
        episodeCount: Math.min(
          60,
          Math.max(
            4,
            recommendedEpisodeCount(
              document.charCount,
              DEFAULT_OPTIONS.durationSeconds,
            ),
          ),
        ),
      };
      setProject({
        ...createProject(),
        name: t("{{title}}·短剧改编", { title: document.title }),
        document,
        characters,
        options,
        phase: "characters",
      });
      setSelectedChapter(0);
      setSelectedEpisode(0);
      setActiveTab("outline");
      setProgress(38);
      setProgressDetail(
        t("已拆解 {{chapters}} 章并识别 {{characters}} 位主要人物", {
          chapters: document.chapters.length,
          characters: characters.length,
        }),
      );
      setToast(t("已导入《{{title}}》", { title: document.title }));
      void runAutomaticNaming(document, characters, options);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : t("文本导入失败"));
    }
  };

  const updateCharacter = (
    id: string,
    patch: Partial<CharacterProfile>,
  ) => {
    setProject((current) => ({
      ...current,
      characters: current.characters.map((character) =>
        character.id === id
          ? {
              ...character,
              ...patch,
              locked: true,
              nameSource: "manual",
            }
          : character,
      ),
      result: null,
      phase: "characters",
    }));
  };

  const openFile = async () => {
    if (window.desktopAPI) {
      try {
        const file = await window.desktopAPI.openTextFile();
        if (file) importText(file.text, file.name);
      } catch {
        setError(t("文件读取失败，请确认文本为 UTF-8 编码"));
      }
      return;
    }
    fileInput.current?.click();
  };

  const onBrowserFile = async (event: ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (file) importText(await file.text(), file.name);
    event.target.value = "";
  };

  const onDrop = async (event: DragEvent) => {
    event.preventDefault();
    const file = event.dataTransfer.files?.[0];
    if (!file) return;
    if (!/\.(txt|md|text)$/i.test(file.name)) {
      setError(t("仅支持 txt、md 或 text 文件"));
      return;
    }
    importText(await file.text(), file.name);
  };

  const updateOptions = (patch: Partial<AdaptationOptions>) => {
    setProject((current) => ({
      ...current,
      options: { ...current.options, ...patch },
      result: null,
      phase: current.document ? "characters" : current.phase,
    }));
  };

  const onPipelinePhase = (
    phase: PipelinePhase,
    detail: string,
    percent: number,
  ) => {
    setProject((current) => ({ ...current, phase }));
    setProgressDetail(detail);
    setProgress(percent);
  };

  const runPipeline = async () => {
    if (!project.document) {
      setError(t("请先导入小说文本"));
      return;
    }
    try {
      setError("");
      setRunning(true);
      setActiveTab("outline");
      let result: AdaptationResult;
      if (useOnline) {
        if (
          !window.desktopAPI ||
          !settings?.hasApiKey ||
          !settings.hasFlashModel
        ) {
          throw new Error(t("请先完成双模型配置"));
        }
        result = await runOnlinePipeline({
          document: project.document,
          characters: project.characters,
          options: project.options,
          promptAssets,
          callStructured: (payload) => window.desktopAPI!.callStructured(payload),
          onCharacters: (characters) =>
            setProject((current) => ({ ...current, characters })),
          onPhase: onPipelinePhase,
        });
      } else {
        const offlineCharacters = resolveModelCharacterNames(
          project.characters,
          project.characters.map((character) => ({
            sourceName: character.sourceName,
            targetName: character.targetName,
          })),
        ).map((character, index) => ({
          ...character,
          nameSource:
            project.characters[index]?.nameSource === "manual"
              ? "manual"
              : "local",
        }) satisfies CharacterProfile);
        assertValidRenameMap(offlineCharacters);
        setProject((current) => ({
          ...current,
          characters: offlineCharacters,
        }));
        const steps: Array<[PipelinePhase, string, number]> = [
          ["analysis", t("正在抽取故事事实、冲突和情绪爆点"), 22],
          ["characters", t("正在应用人物改名表并检查重名"), 38],
          ["outline", t("正在重组分集目标、反转与卡点"), 55],
          ["drafting", t("正在生成场景动作和角色对白"), 76],
          ["quality", t("正在检查旧名、结构、钩子与内容风险"), 92],
        ];
        for (const [phase, detail, percent] of steps) {
          onPipelinePhase(phase, detail, percent);
          await wait(180);
        }
        result = buildOfflineAdaptation(
          project.document,
          offlineCharacters,
          project.options,
        );
      }
      const passedQualityGate = result.quality.passed;
      setProject((current) => ({
        ...current,
        result,
        phase: passedQualityGate ? "completed" : "quality",
      }));
      setProgress(100);
      setProgressDetail(
        passedQualityGate
          ? t("已完成 {{episodes}} 集，质检 {{score}} 分", {
              episodes: result.episodes.length,
              score: result.quality.score,
            })
          : t("成稿已生成，但未通过完整度质量门（{{score}} 分）", {
              score: result.quality.score,
            }),
      );
      setActiveTab(passedQualityGate ? "script" : "quality");
      setSelectedEpisode(0);
      if (passedQualityGate) {
        setToast(t("改编完成，已保存到本地项目"));
      } else {
        const completenessDetail =
          result.quality.metrics.find(
            (metric) => metric.id === "completeness",
          )?.detail || t("请查看质检报告中的成稿完整度");
        setError(
          t("自动重写后仍有未达线分集：{{detail}}。成稿已保留，可查看质检报告或重新生成。", {
            detail: completenessDetail,
          }),
        );
      }
    } catch (caught) {
      const message = cleanAppError(caught, t("生成失败"));
      setError(message);
      setProject((current) => ({ ...current, phase: "failed" }));
    } finally {
      setRunning(false);
    }
  };

  const exportScript = async () => {
    if (!project.result) {
      setError(t("暂无可导出的剧本"));
      return;
    }
    const content = projectExport(project.result, project, t);
    if (window.desktopAPI) {
      const path = await window.desktopAPI.saveTextFile({
        fileName: project.name,
        content,
      });
      if (path) setToast(t("已导出：{{path}}", { path }));
      return;
    }
    const blob = new Blob([content], { type: "text/plain;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = `${project.name}.txt`;
    anchor.click();
    URL.revokeObjectURL(url);
    setToast(t("已导出 UTF-8 文本"));
  };

  const runBookAnalysis = async () => {
    if (!project.document) {
      setError(t("请先导入小说文本"));
      return;
    }
    try {
      setError("");
      setBookRunning(true);
      setBookProgress({
        stage: "preparing",
        completed: 0,
        total: 0,
        percent: 1,
        message: t("正在准备全书证据"),
      });
      const onlineReady = Boolean(
        window.desktopAPI && settings?.hasApiKey && settings.hasFlashModel,
      );
      const result = onlineReady
        ? await runOnlineBookAnalysis({
            document: project.document,
            characters: project.characters,
            callStructured: (payload) =>
              window.desktopAPI!.callStructured(payload),
            onProgress: setBookProgress,
          })
        : buildOfflineBookAnalysis(project.document, project.characters);
      setProject((current) => ({
        ...current,
        bookAnalysis: result,
      }));
      setBookProgress({
        stage: "done",
        completed: result.analyzedChunks,
        total: result.totalChunks,
        percent: 100,
        message: t("一键拆书完成"),
      });
      setToast(
        t(
          onlineReady
            ? "全书深度拆解完成，报告已保存"
            : "本地基础拆解完成；配置双模型后可生成深度报告",
        ),
      );
    } catch (caught) {
      setError(cleanAppError(caught, t("一键拆书失败")));
    } finally {
      setBookRunning(false);
    }
  };

  const reviseCurrentBookAnalysis = async (instruction: string) => {
    if (!project.document || !project.bookAnalysis) return;
    if (
      !window.desktopAPI ||
      !settings?.hasApiKey ||
      !settings.hasFlashModel
    ) {
      setError(t("报告微调需要先完成双模型配置"));
      return;
    }
    try {
      setError("");
      setBookRevising(true);
      const revised = await reviseBookAnalysis({
        result: project.bookAnalysis,
        document: project.document,
        instruction,
        callStructured: (payload) =>
          window.desktopAPI!.callStructured(payload),
      });
      setProject((current) => ({
        ...current,
        bookAnalysis: revised,
      }));
      setToast(t("拆书报告已按指令更新"));
    } catch (caught) {
      setError(cleanAppError(caught, t("拆书报告微调失败")));
    } finally {
      setBookRevising(false);
    }
  };

  const selectCurrentBookVersion = (index: number) => {
    setProject((current) => ({
      ...current,
      bookAnalysis: current.bookAnalysis
        ? selectBookAnalysisVersion(current.bookAnalysis, index)
        : current.bookAnalysis,
    }));
  };

  const exportBookAnalysis = async () => {
    if (!project.bookAnalysis) {
      setError(t("暂无可导出的拆书报告"));
      return;
    }
    const content = renderBookAnalysisMarkdown(project.bookAnalysis);
    const fileName = `${project.document?.title || project.name}·拆书报告`;
    if (window.desktopAPI) {
      const path = await window.desktopAPI.saveTextFile({
        fileName,
        content,
        extension: "md",
      });
      if (path) setToast(t("已导出：{{path}}", { path }));
      return;
    }
    const blob = new Blob([content], {
      type: "text/markdown;charset=utf-8",
    });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = `${fileName}.md`;
    anchor.click();
    URL.revokeObjectURL(url);
    setToast(t("拆书报告已导出"));
  };

  const updateEpisodeContent = (content: string) => {
    setProject((current) => {
      if (!current.result) return current;
      return {
        ...current,
        result: {
          ...current.result,
          episodes: current.result.episodes.map((episode, index) =>
            index === selectedEpisode ? { ...episode, content } : episode,
          ),
        },
      };
    });
  };

  const openProject = (item: StoredProject) => {
    setProject(structuredClone(item));
    setSelectedChapter(0);
    setSelectedEpisode(0);
    setActiveTab(item.result ? "script" : "outline");
    setProgress(item.result ? 100 : item.document ? 38 : 0);
    setProgressDetail("");
    setPrimaryView("studio");
    setBookProgress({
      stage: item.bookAnalysis ? "done" : "preparing",
      completed: item.bookAnalysis?.analyzedChunks || 0,
      total: item.bookAnalysis?.totalChunks || 0,
      percent: item.bookAnalysis ? 100 : 0,
      message: item.bookAnalysis ? t("一键拆书完成") : "",
    });
  };

  const saveCurrentProjectToLibrary = () => {
    if (!project.document && !project.result) return;
    const snapshot = {
      ...structuredClone(project),
      updatedAt: new Date().toISOString(),
    };
    setProjectLibrary((current) => {
      return persistProjectLibrary(upsertProject(current, snapshot));
    });
  };

  const createNewProject = () => {
    saveCurrentProjectToLibrary();
    openProject(createProject());
    setToast(t("已新建空白改编项目"));
  };

  const resetHome = () => {
    const archived = Boolean(project.document || project.result);
    saveCurrentProjectToLibrary();
    openProject(createProject());
    setError("");
    setToast(
      t(
        archived
          ? "已重置到初始首页；原项目已保存在项目档案"
          : "已重置到初始首页",
      ),
    );
  };

  const duplicateProject = (item: StoredProject) => {
    const copy: StoredProject = {
      ...structuredClone(item),
      id: crypto.randomUUID(),
      name: t("{{name}} · 副本", { name: item.name }),
      updatedAt: new Date().toISOString(),
      archivedAt: undefined,
    };
    setProjectLibrary((current) => {
      return persistProjectLibrary(upsertProject(current, copy));
    });
    openProject(copy);
    setToast(t("项目副本已创建"));
  };

  const archiveProjectCard = (item: StoredProject) => {
    const archivedAt = new Date().toISOString();
    setProjectLibrary((current) =>
      persistProjectLibrary(
        archiveProjectInLibrary(current, item.id, archivedAt),
      ),
    );
    if (project.id === item.id) {
      setProject((current) => ({ ...current, archivedAt }));
    }
    setToast(t("项目已归档"));
  };

  const restoreProjectCard = (item: StoredProject) => {
    const restoredAt = new Date().toISOString();
    setProjectLibrary((current) =>
      persistProjectLibrary(
        restoreProjectInLibrary(current, item.id, restoredAt),
      ),
    );
    if (project.id === item.id) {
      setProject((current) => ({
        ...current,
        archivedAt: undefined,
        updatedAt: restoredAt,
      }));
    }
    setToast(t("项目已恢复到最近项目"));
  };

  const deleteProjectCard = (item: StoredProject) => {
    if (!item.archivedAt) return;
    setPendingDelete(item);
  };

  const confirmDeleteProject = () => {
    if (!pendingDelete?.archivedAt) return;
    const item = pendingDelete;
    setProjectLibrary((current) =>
      persistProjectLibrary(
        deleteArchivedProjectInLibrary(current, item.id),
      ),
    );
    setPendingDelete(null);
    if (project.id === item.id) {
      openProject(createProject());
      setError("");
      setToast(t("项目已永久删除，已返回初始首页"));
      return;
    }
    setToast(t("项目已永久删除"));
  };

  const updatePromptAsset = (id: PromptAsset["id"], content: string) => {
    setPromptAssets((current) =>
      current.map((asset) => (asset.id === id ? { ...asset, content } : asset)),
    );
  };

  const resetPromptAsset = (id: PromptAsset["id"]) => {
    const fallback = DEFAULT_PROMPT_ASSETS.find((asset) => asset.id === id);
    if (!fallback) return;
    setPromptAssets((current) =>
      current.map((asset) => (asset.id === id ? { ...fallback } : asset)),
    );
    setToast(t("提示词已恢复默认"));
  };

  return (
    <div className="app-shell" onDragOver={(event) => event.preventDefault()} onDrop={onDrop}>
      <input
        ref={fileInput}
        className="visually-hidden"
        type="file"
        accept=".txt,.md,.text,text/plain"
        onChange={onBrowserFile}
      />
      <aside className="sidebar">
        <div className="brand">
          <div className="brand-mark">
            <Clapperboard size={21} strokeWidth={2.4} />
          </div>
          <div>
            <strong>{t("剧擎")}</strong>
            <span>SCRIPT FORGE</span>
          </div>
        </div>

        <nav className="primary-nav">
          <button
            className={`nav-item ${primaryView === "book" ? "active" : ""}`}
            onClick={() => setPrimaryView("book")}
          >
            <BookOpen size={17} />
            {t("一键拆书")}
          </button>
          <button
            className={`nav-item ${primaryView === "studio" ? "active" : ""}`}
            onClick={() => setPrimaryView("studio")}
          >
            <WandSparkles size={17} />
            {t("改编工坊")}
          </button>
          <button
            className={`nav-item ${primaryView === "projects" ? "active" : ""}`}
            onClick={() => setPrimaryView("projects")}
          >
            <FolderKanban size={17} />
            {t("项目档案")}
            <span className="nav-count">{recentProjectCount}</span>
          </button>
          <button
            className={`nav-item ${primaryView === "prompts" ? "active" : ""}`}
            onClick={() => setPrimaryView("prompts")}
          >
            <Library size={17} />
            {t("提示词资产")}
          </button>
        </nav>

        <div className="sidebar-section">
          <div className="section-label">
            <span>{t("当前项目")}</span>
            <MoreHorizontal size={15} />
          </div>
          <button
            className={`project-tile ${primaryView === "studio" ? "active" : ""}`}
            onClick={() => setPrimaryView("studio")}
          >
            <div className="project-thumb">
              <BookOpen size={17} />
            </div>
            <div>
              <strong>{project.document ? project.document.title : t("尚未导入")}</strong>
              <span>
                {project.document
                  ? t("{{chapters}}章 · {{episodes}}集", {
                      chapters: project.document.chapters.length,
                      episodes: project.result?.episodes.length || "—",
                    })
                  : t("导入小说后开始")}
              </span>
            </div>
          </button>
        </div>

        <div className="sidebar-insight">
          <div className="eyebrow">
            <Sparkles size={13} />
            {t("创作策略 2026")}
          </div>
          <strong>{t("爽点只是引擎，人物选择才是余味。")}</strong>
          <p>{t("默认采用精品化、类型融合、现实落点的短剧结构。")}</p>
        </div>

        <div className="sidebar-bottom">
          <button onClick={() => setSettingsOpen(true)}>
            <Settings size={17} />
            {t("模型与偏好")}
            <span
              className={`status-dot ${
                settings?.hasApiKey && settings.hasFlashModel ? "online" : ""
              }`}
            />
          </button>
          <button onClick={() => setPrimaryView("projects")}>
            <History size={17} />
            {t("本地自动保存")}
          </button>
          <div className="profile">
            <div className="avatar">{locale === "en-US" ? "S" : "编"}</div>
            <div>
              <strong>{t("本地创作空间")}</strong>
              <span>{t("数据保存在此电脑")}</span>
            </div>
          </div>
        </div>
      </aside>

      <main className="main-area">
        <header className="topbar">
          <div className="project-heading">
            <div className="breadcrumb">
              {t(
                primaryView === "book"
                  ? "创作系统 / 一键拆书"
                  : primaryView === "studio"
                    ? "改编工坊 / 当前项目"
                    : primaryView === "projects"
                      ? "本地工作区 / 项目档案"
                      : "创作系统 / 提示词资产",
              )}
            </div>
            {primaryView === "studio" ? (
              <input
                value={project.name}
                onChange={(event) =>
                  setProject((current) => ({ ...current, name: event.target.value }))
                }
                aria-label={t("项目名称")}
              />
            ) : (
              <h1>
                {t(
                  primaryView === "book"
                    ? "一键拆书"
                    : primaryView === "projects"
                      ? "项目档案"
                      : "提示词资产",
                )}
              </h1>
            )}
          </div>
          <div className="top-actions">
            <div className="save-state">
              <Save size={14} />
              {t("本地已保存")}
            </div>
            <div className="language-switcher" aria-label={t("语言")}>
              <Languages size={14} />
              <button
                className={locale === "zh-CN" ? "active" : ""}
                onClick={() => setLocale("zh-CN")}
              >
                中
              </button>
              <span>/</span>
              <button
                className={locale === "en-US" ? "active" : ""}
                onClick={() => setLocale("en-US")}
              >
                EN
              </button>
            </div>
            {primaryView === "studio" && (
              <button
                className="button secondary reset-home-button"
                onClick={resetHome}
                title={t("重置到未导入小说的初始首页")}
              >
                <RotateCcw size={15} />
                {t("重置首页")}
              </button>
            )}
            <button className="button secondary" onClick={openFile}>
              <Import size={16} />
              {t("导入小说")}
            </button>
            <button
              className="button dark"
              onClick={
                primaryView === "book" ? exportBookAnalysis : exportScript
              }
              disabled={
                primaryView === "book"
                  ? !project.bookAnalysis
                  : !project.result
              }
            >
              <Download size={16} />
              {t(primaryView === "book" ? "导出报告" : "导出成稿")}
            </button>
          </div>
        </header>

        {primaryView === "book" ? (
          <BookAnalysisWorkspace
            project={project}
            settings={settings}
            running={bookRunning}
            revising={bookRevising}
            progress={bookProgress}
            onImport={openFile}
            onRun={runBookAnalysis}
            onRevise={reviseCurrentBookAnalysis}
            onSelectVersion={selectCurrentBookVersion}
            onExport={exportBookAnalysis}
            onOpenSettings={() => setSettingsOpen(true)}
          />
        ) : primaryView === "projects" ? (
          <ProjectArchiveWorkspace
            projects={
              projectLibrary.some((item) => item.id === project.id)
                ? projectLibrary
                : [project, ...projectLibrary]
            }
            currentProjectId={project.id}
            onOpen={openProject}
            onDuplicate={duplicateProject}
            onArchive={archiveProjectCard}
            onRestore={restoreProjectCard}
            onDelete={deleteProjectCard}
            onNew={createNewProject}
          />
        ) : primaryView === "prompts" ? (
          <PromptAssetsWorkspace
            assets={promptAssets}
            onUpdate={updatePromptAsset}
            onReset={resetPromptAsset}
          />
        ) : !project.document ? (
          <EmptyWorkspace onImport={openFile} />
        ) : (
          <>
            <section className="pipeline-strip">
              <div className="pipeline-title">
                <div className={`pulse ${running ? "running" : ""}`} />
                <div>
                  <strong>{t(running ? "改编管线运行中" : "结构化改编管线")}</strong>
                  <span>{progressDetail || t("人物表已就绪，角色名称可继续手动修改")}</span>
                </div>
              </div>
              <div className="phase-rail">
                {PHASES.map((phase, index) => {
                  const phaseIndex = PHASE_ORDER.indexOf(phase.id);
                  const completed =
                    project.phase === "completed" || currentPhaseIndex > phaseIndex;
                  const active = project.phase === phase.id;
                  return (
                    <div
                      key={phase.id}
                      className={`phase ${completed ? "done" : ""} ${active ? "active" : ""}`}
                    >
                      <span>{completed ? <Check size={12} /> : index + 1}</span>
                      {t(phase.label)}
                    </div>
                  );
                })}
              </div>
              <div className="progress-bar">
                <span style={{ width: `${progress}%` }} />
              </div>
            </section>

            <section className="workspace-grid">
              <SourcePanel
                project={project}
                selectedChapter={selectedChapter}
                onSelectChapter={setSelectedChapter}
                selectedChapterData={selectedChapterData}
                onImport={openFile}
              />

              <section className="studio-panel panel">
                <div className="studio-toolbar">
                  <div className="tabs">
                    <button
                      className={activeTab === "outline" ? "active" : ""}
                      onClick={() => setActiveTab("outline")}
                    >
                      {t("分集设计")}
                    </button>
                    <button
                      className={activeTab === "script" ? "active" : ""}
                      onClick={() => setActiveTab("script")}
                      disabled={!project.result}
                    >
                      {t("剧本编辑")}
                    </button>
                    <button
                      className={activeTab === "bible" ? "active" : ""}
                      onClick={() => setActiveTab("bible")}
                      disabled={!project.result?.storyBible}
                    >
                      {t("全剧圣经")}
                    </button>
                    <button
                      className={activeTab === "quality" ? "active" : ""}
                      onClick={() => setActiveTab("quality")}
                      disabled={!project.result}
                    >
                      {t("质检报告")}
                    </button>
                  </div>
                  <button className="icon-button" aria-label={t("搜索")}>
                    <Search size={17} />
                  </button>
                </div>

                {activeTab === "outline" && (
                  <OutlineWorkspace
                    project={project}
                    useOnline={useOnline}
                    settings={settings}
                    running={running}
                    onUseOnline={setUseOnline}
                    onUpdateOptions={updateOptions}
                    onRun={runPipeline}
                    onOpenSettings={() => setSettingsOpen(true)}
                  />
                )}
                {activeTab === "script" && project.result && (
                  <ScriptWorkspace
                    project={project}
                    selectedEpisode={selectedEpisode}
                    onSelectEpisode={setSelectedEpisode}
                    episode={selectedEpisodeData}
                    onChangeContent={updateEpisodeContent}
                  />
                )}
                {activeTab === "bible" && project.result?.storyBible && (
                  <BibleWorkspace result={project.result} />
                )}
                {activeTab === "quality" && project.result && (
                  <QualityWorkspace result={project.result} />
                )}
              </section>

              <CharacterPanel
                project={project}
                onUpdateCharacter={updateCharacter}
                onOpenQuality={() => setActiveTab("quality")}
              />
            </section>
          </>
        )}
      </main>

      {error && (
        <div className="error-toast">
          <X size={16} />
          <span>{error}</span>
          <button onClick={() => setError("")}>{t("知道了")}</button>
        </div>
      )}
      {toast && <div className="success-toast">{toast}</div>}
      {pendingDelete && (
        <DeleteProjectDialog
          project={pendingDelete}
          onCancel={() => setPendingDelete(null)}
          onConfirm={confirmDeleteProject}
        />
      )}
      {settingsOpen && (
        <SettingsDialog
          settings={settings}
          onClose={() => setSettingsOpen(false)}
          onSaved={(value) => {
            setSettings(value);
            setUseOnline(value.hasApiKey && value.hasFlashModel);
            setSettingsOpen(false);
            setToast(t("模型设置已安全保存"));
            if (project.document) {
              void runAutomaticNaming(
                project.document,
                project.characters,
                project.options,
                value,
              );
            }
          }}
        />
      )}
    </div>
  );
}

function DeleteProjectDialog({
  project,
  onCancel,
  onConfirm,
}: {
  project: StoredProject;
  onCancel: () => void;
  onConfirm: () => void;
}) {
  const { t } = useI18n();

  return (
    <div className="modal-backdrop" onMouseDown={onCancel}>
      <div
        className="confirm-dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby="delete-project-title"
        onMouseDown={(event) => event.stopPropagation()}
      >
        <div className="delete-dialog-icon">
          <Trash2 size={21} />
        </div>
        <div>
          <h2 id="delete-project-title">{t("永久删除项目")}</h2>
          <p>
            {t("确定永久删除项目“{{name}}”吗？此操作无法撤销。", {
              name: project.name,
            })}
          </p>
        </div>
        <div className="dialog-actions">
          <button className="button secondary" onClick={onCancel}>
            {t("取消")}
          </button>
          <button
            className="button danger"
            data-testid="confirm-project-delete"
            onClick={onConfirm}
          >
            <Trash2 size={15} />
            {t("永久删除")}
          </button>
        </div>
      </div>
    </div>
  );
}

function BookAnalysisWorkspace({
  project,
  settings,
  running,
  revising,
  progress,
  onImport,
  onRun,
  onRevise,
  onSelectVersion,
  onExport,
  onOpenSettings,
}: {
  project: StoredProject;
  settings: ModelSettings | null;
  running: boolean;
  revising: boolean;
  progress: BookAnalysisProgress;
  onImport: () => void;
  onRun: () => void;
  onRevise: (instruction: string) => Promise<void>;
  onSelectVersion: (index: number) => void;
  onExport: () => void;
  onOpenSettings: () => void;
}) {
  const { locale, t } = useI18n();
  const [revision, setRevision] = useState("");
  const document = project.document;
  const result = project.bookAnalysis;
  const report = result?.report;
  const modelReady = Boolean(settings?.hasApiKey && settings.hasFlashModel);
  const submitRevision = async () => {
    const instruction = revision.trim();
    if (!instruction || revising) return;
    await onRevise(instruction);
    setRevision("");
  };
  const chapterLabel = (ids: string[]) => {
    if (!document || !ids.length) return t("证据待复核");
    const byId = new Map(
      document.chapters.map((chapter) => [
        chapter.id,
        t("第 {{number}} 章", { number: chapter.index }),
      ]),
    );
    return ids.map((id) => byId.get(id) || id).join("、");
  };
  const Evidence = ({ ids }: { ids: string[] }) => (
    <span className="book-evidence">
      <ShieldCheck size={12} />
      {chapterLabel(ids)}
    </span>
  );

  if (!document) {
    return (
      <section className="book-analysis-workspace book-analysis-empty">
        <div className="book-empty-copy">
          <span className="kicker">ONE-CLICK BOOK ANALYSIS</span>
          <h2>{t("一键读完全书，拆出真正可复用的写作逻辑。")}</h2>
          <p>
            {t(
              "完整覆盖章节证据，自动分析叙事结构、人物体系、爽点卖点、文笔风格和仿写方法。",
            )}
          </p>
          <button className="button primary large" onClick={onImport}>
            <UploadCloud size={19} />
            {t("导入小说并开始")}
          </button>
          <small>{t("支持 UTF-8 编码的 TXT / MD 文件")}</small>
        </div>
        <div className="book-empty-flow">
          {[
            ["01", t("全书证据切片"), t("长章继续按叙事边界拆分，不截断正文")],
            ["02", t("事实分层压缩"), t("保留人物、事件、伏笔、钩子与文风信号")],
            ["03", t("三路专项分析"), t("结构、人物、卖点与技法分别深挖")],
            ["04", t("章节证据质检"), t("每个核心判断都能返回原文章节")],
          ].map((item) => (
            <div key={item[0]} className="book-flow-row">
              <span>{item[0]}</span>
              <div>
                <strong>{item[1]}</strong>
                <p>{item[2]}</p>
              </div>
            </div>
          ))}
        </div>
      </section>
    );
  }

  return (
    <section className="book-analysis-workspace">
      <div className="book-analysis-hero">
        <div className="book-hero-copy">
          <span className="kicker">ONE-CLICK BOOK ANALYSIS</span>
          <h2>{t("从全书证据到可复用方法，一次完成。")}</h2>
          <p>
            {t(
              "系统自动完成全文覆盖、证据压缩、专项分析和完整度校验；模型分工无需手动设置。",
            )}
          </p>
        </div>
        <div className="book-hero-actions">
          <div className={`book-model-state ${modelReady ? "online" : ""}`}>
            {modelReady ? <Cloud size={16} /> : <ShieldCheck size={16} />}
            <span>
              {t(modelReady ? "双模型深度拆书已就绪" : "将使用本地基础拆书")}
            </span>
          </div>
          {!modelReady && (
            <button className="text-button" onClick={onOpenSettings}>
              {t("配置双模型")}
            </button>
          )}
          <button
            className="button primary book-run-button"
            onClick={onRun}
            disabled={running}
          >
            {running ? (
              <RefreshCw className="spin" size={17} />
            ) : (
              <Sparkles size={17} />
            )}
            {t(
              running
                ? "正在一键拆书"
                : result
                  ? "重新一键拆书"
                  : "开始一键拆书",
            )}
          </button>
        </div>
      </div>

      <div className="book-source-strip">
        <div>
          <BookOpen size={19} />
          <span>
            <strong>{document.title}</strong>
            <small>
              {document.author !== "未知"
                ? document.author
                : document.fileName}
            </small>
          </span>
        </div>
        <div>
          <strong>{document.chapters.length}</strong>
          <span>{t("章节")}</span>
        </div>
        <div>
          <strong>{formatNumber(document.charCount)}</strong>
          <span>{t("字符")}</span>
        </div>
        <div>
          <strong>{result?.coveragePercent ?? 0}%</strong>
          <span>{t("证据覆盖")}</span>
        </div>
      </div>

      {(running || progress.percent > 0) && (
        <div className={`book-progress ${running ? "running" : ""}`}>
          <div>
            <span>{progress.message || t("准备开始拆书")}</span>
            <b>{progress.percent}%</b>
          </div>
          <div className="book-progress-track">
            <span style={{ width: `${progress.percent}%` }} />
          </div>
          {progress.total > 0 && (
            <small>
              {t("已处理 {{completed}} / {{total}} 个证据单元", {
                completed: progress.completed,
                total: progress.total,
              })}
            </small>
          )}
        </div>
      )}

      {!report ? (
        <div className="book-ready-state">
          <div>
            <CircleGauge size={26} />
            <strong>{t("小说已就绪，可以开始一键拆书")}</strong>
            <p>
              {t(
                "报告将覆盖书籍元信息、叙事结构、人物关系、爽点卖点、文笔风格与仿写指南。",
              )}
            </p>
          </div>
          <div className="book-ready-grid">
            {[
              t("开篇钩子与节奏曲线"),
              t("人物弧光与反派梯队"),
              t("爽点密度与商业卖点"),
              t("文风证据与可复用技法"),
            ].map((item) => (
              <span key={item}>
                <CheckCircle2 size={14} />
                {item}
              </span>
            ))}
          </div>
        </div>
      ) : (
        <div className="book-report">
          <div className="book-report-heading">
            <div>
              <span className="eyebrow">ANALYSIS REPORT</span>
              <h2>《{report.title}》{t("拆书报告")}</h2>
              <p>
                {t(
                  "{{mode}} · {{chunks}} 个证据块 · 生成于 {{time}}",
                  {
                    mode: t(
                      result.mode === "online"
                        ? "双模型深度分析"
                        : "本地基础分析",
                    ),
                    chunks: result.totalChunks,
                    time: new Date(result.generatedAt).toLocaleString(
                      locale === "en-US" ? "en-US" : "zh-CN",
                      { dateStyle: "medium", timeStyle: "short" },
                    ),
                  },
                )}
              </p>
            </div>
            <button className="button secondary" onClick={onExport}>
              <Download size={15} />
              {t("导出 Markdown")}
            </button>
          </div>

          {result.versions.length > 1 && (
            <div className="book-version-row">
              <span>{t("报告版本")}</span>
              {result.versions.map((version, index) => (
                <button
                  key={version.id}
                  className={result.currentVersion === index ? "active" : ""}
                  onClick={() => onSelectVersion(index)}
                  title={version.instruction}
                >
                  v{index + 1}
                </button>
              ))}
            </div>
          )}

          {result.warnings.length > 0 && (
            <div className="book-warning">
              <ShieldCheck size={17} />
              <div>
                <strong>{t("质检提示")}</strong>
                {result.warnings.map((warning) => (
                  <p key={warning}>{warning}</p>
                ))}
              </div>
            </div>
          )}

          <div className="book-report-sections">
            <details open>
              <summary>
                <span>01</span>
                <strong>{t("书籍元信息")}</strong>
                <ChevronDown size={16} />
              </summary>
              <div className="book-section-content">
                <div className="book-meta-grid">
                  <div>
                    <span>{t("类型标签")}</span>
                    <strong>{report.meta.genreTags.join(" · ")}</strong>
                  </div>
                  <div>
                    <span>{t("综合评分")}</span>
                    <strong>{report.learning.score}/10</strong>
                  </div>
                </div>
                <h4>{t("一句话卖点")}</h4>
                <p>{report.meta.logline}</p>
                <h4>{t("故事梗概")}</h4>
                <p>{report.meta.summary}</p>
                <h4>{t("目标读者")}</h4>
                <p>{report.meta.targetReader}</p>
              </div>
            </details>

            <details open>
              <summary>
                <span>02</span>
                <strong>{t("叙事结构深度分析")}</strong>
                <ChevronDown size={16} />
              </summary>
              <div className="book-section-content">
                <h4>{t("结构归类")}</h4>
                <p>{report.structure.classification}</p>
                <h4>{t("黄金开篇")}</h4>
                <p>{report.structure.openingHook}</p>
                <h4>{t("节奏总览")}</h4>
                <p>{report.structure.rhythmOverview}</p>
                <div className="book-phase-list">
                  {report.structure.phases.map((phase) => (
                    <article key={`${phase.name}-${phase.chapterRange}`}>
                      <div>
                        <strong>{phase.name}</strong>
                        <span>{phase.chapterRange}</span>
                      </div>
                      <p>{phase.description}</p>
                      <small>
                        {phase.rhythm} · {phase.highlightDensity}
                      </small>
                      <Evidence ids={phase.evidenceChapterIds} />
                    </article>
                  ))}
                </div>
                <h4>{t("伏笔与回收")}</h4>
                {report.structure.foreshadowing.length ? (
                  <div className="book-insight-list">
                    {report.structure.foreshadowing.map((item) => (
                      <article key={`${item.content}-${item.planted}`}>
                        <strong>{item.content}</strong>
                        <p>
                          {item.planted} → {item.revealed} · {item.quality}
                        </p>
                        <Evidence ids={item.evidenceChapterIds} />
                      </article>
                    ))}
                  </div>
                ) : (
                  <p className="muted-copy">{t("暂无可靠证据")}</p>
                )}
                <BookProsCons
                  strengths={report.structure.strengths}
                  risks={report.structure.risks}
                />
              </div>
            </details>

            <details>
              <summary>
                <span>03</span>
                <strong>{t("人物体系分析")}</strong>
                <ChevronDown size={16} />
              </summary>
              <div className="book-section-content">
                <BookCharacterCard
                  character={report.characters.protagonist}
                  label={t("主角")}
                  evidence={Evidence}
                />
                <div className="book-character-grid">
                  {report.characters.antagonists.map((character) => (
                    <BookCharacterCard
                      key={`antagonist-${character.name}`}
                      character={character}
                      label={t("反派")}
                      evidence={Evidence}
                    />
                  ))}
                  {report.characters.supporting.map((character) => (
                    <BookCharacterCard
                      key={`supporting-${character.name}`}
                      character={character}
                      label={t("配角")}
                      evidence={Evidence}
                    />
                  ))}
                </div>
                <h4>{t("人物关系总览")}</h4>
                <p>{report.characters.relationshipOverview}</p>
                <h4>{t("人物体系总评")}</h4>
                <p>{report.characters.evaluation}</p>
              </div>
            </details>

            <details>
              <summary>
                <span>04</span>
                <strong>{t("爽点与卖点深度分析")}</strong>
                <ChevronDown size={16} />
              </summary>
              <div className="book-section-content">
                <p>{report.highlights.overview}</p>
                <div className="book-highlight-grid">
                  {report.highlights.categories.map((item) => (
                    <article key={`${item.type}-${item.intensity}`}>
                      <div>
                        <strong>{item.type}</strong>
                        <span>{item.intensity}</span>
                      </div>
                      <p>{item.mechanism}</p>
                      <ul>
                        {item.representativeScenes.map((scene) => (
                          <li key={scene}>{scene}</li>
                        ))}
                      </ul>
                      <Evidence ids={item.evidenceChapterIds} />
                    </article>
                  ))}
                </div>
                <div className="book-density-grid">
                  <div>
                    <span>{t("爽点高峰")}</span>
                    <strong>{report.highlights.peakZone}</strong>
                  </div>
                  <div>
                    <span>{t("爽点低谷")}</span>
                    <strong>{report.highlights.droughtZone}</strong>
                  </div>
                  <div>
                    <span>{t("平均间隔")}</span>
                    <strong>{report.highlights.averageInterval}</strong>
                  </div>
                </div>
                <BookProsCons
                  strengths={report.highlights.strengths}
                  risks={report.highlights.risks}
                />
              </div>
            </details>

            <details>
              <summary>
                <span>05</span>
                <strong>{t("文笔与写作技法分析")}</strong>
                <ChevronDown size={16} />
              </summary>
              <div className="book-section-content">
                <BookLabeledParagraph label={t("语言风格")} text={report.style.language} />
                <BookLabeledParagraph label={t("叙事方式")} text={report.style.narration} />
                <BookLabeledParagraph label={t("场景描写")} text={report.style.sceneWriting} />
                <BookLabeledParagraph label={t("对话特色")} text={report.style.dialogue} />
                <BookLabeledParagraph label={t("情绪调动")} text={report.style.emotionalControl} />
                <BookTechniqueList
                  techniques={report.style.techniques}
                  evidence={Evidence}
                />
              </div>
            </details>

            <details>
              <summary>
                <span>06</span>
                <strong>{t("学习与仿写实操指南")}</strong>
                <ChevronDown size={16} />
              </summary>
              <div className="book-section-content">
                <BookTechniqueList
                  techniques={report.learning.techniques}
                  evidence={Evidence}
                />
                <BookNumberedList
                  title={t("结构复用方案")}
                  items={report.learning.structureBlueprint}
                />
                <BookNumberedList
                  title={t("仿写方向")}
                  items={report.learning.imitationDirections}
                />
                <BookNumberedList
                  title={t("需要规避")}
                  items={report.learning.pitfalls}
                />
                <div className="book-recommendation">
                  <strong>{report.learning.score}/10</strong>
                  <p>{report.learning.recommendation}</p>
                </div>
              </div>
            </details>
          </div>

          <div className="book-revision">
            <div>
              <Bot size={18} />
              <span>
                <strong>{t("对话微调报告")}</strong>
                <small>{t("只修改相关段落，并保留章节证据和历史版本")}</small>
              </span>
            </div>
            <textarea
              value={revision}
              onChange={(event) => setRevision(event.target.value)}
              placeholder={t("例如：加强对前三章钩子和读者留存的分析")}
              disabled={revising}
            />
            <button
              className="button primary"
              onClick={submitRevision}
              disabled={!revision.trim() || revising || !modelReady}
            >
              {revising ? (
                <RefreshCw className="spin" size={15} />
              ) : (
                <PenLine size={15} />
              )}
              {t(revising ? "正在更新" : "更新报告")}
            </button>
          </div>
        </div>
      )}
    </section>
  );
}

function BookCharacterCard({
  character,
  label,
  evidence: Evidence,
}: {
  character: BookAnalysisResult["report"]["characters"]["protagonist"];
  label: string;
  evidence: ({ ids }: { ids: string[] }) => ReactNode;
}) {
  const { t } = useI18n();
  return (
    <article className="book-character-card">
      <div>
        <span>{label}</span>
        <strong>{character.name}</strong>
      </div>
      <p>{character.identity}</p>
      <dl>
        <dt>{t("叙事功能")}</dt>
        <dd>{character.narrativeFunction}</dd>
        <dt>{t("核心动机")}</dt>
        <dd>{character.motivation}</dd>
        <dt>{t("成长弧")}</dt>
        <dd>{character.arc}</dd>
      </dl>
      <Evidence ids={character.evidenceChapterIds} />
    </article>
  );
}

function BookProsCons({
  strengths,
  risks,
}: {
  strengths: string[];
  risks: string[];
}) {
  const { t } = useI18n();
  return (
    <div className="book-pros-cons">
      <div>
        <strong>{t("优势")}</strong>
        <ul>
          {strengths.map((item) => (
            <li key={item}>{item}</li>
          ))}
        </ul>
      </div>
      <div>
        <strong>{t("风险")}</strong>
        <ul>
          {risks.map((item) => (
            <li key={item}>{item}</li>
          ))}
        </ul>
      </div>
    </div>
  );
}

function BookLabeledParagraph({
  label,
  text,
}: {
  label: string;
  text: string;
}) {
  return (
    <>
      <h4>{label}</h4>
      <p>{text}</p>
    </>
  );
}

function BookTechniqueList({
  techniques,
  evidence: Evidence,
}: {
  techniques: BookAnalysisResult["report"]["learning"]["techniques"];
  evidence: ({ ids }: { ids: string[] }) => ReactNode;
}) {
  return (
    <div className="book-technique-list">
      {techniques.map((technique) => (
        <article key={`${technique.name}-${technique.observation}`}>
          <strong>{technique.name}</strong>
          <p>{technique.observation}</p>
          <small>{technique.reusableMethod}</small>
          <Evidence ids={technique.evidenceChapterIds} />
        </article>
      ))}
    </div>
  );
}

function BookNumberedList({
  title,
  items,
}: {
  title: string;
  items: string[];
}) {
  return (
    <div className="book-numbered-list">
      <h4>{title}</h4>
      {items.map((item, index) => (
        <div key={item}>
          <span>{String(index + 1).padStart(2, "0")}</span>
          <p>{item}</p>
        </div>
      ))}
    </div>
  );
}

function ProjectArchiveWorkspace({
  projects,
  currentProjectId,
  onOpen,
  onDuplicate,
  onArchive,
  onRestore,
  onDelete,
  onNew,
}: {
  projects: StoredProject[];
  currentProjectId: string;
  onOpen: (project: StoredProject) => void;
  onDuplicate: (project: StoredProject) => void;
  onArchive: (project: StoredProject) => void;
  onRestore: (project: StoredProject) => void;
  onDelete: (project: StoredProject) => void;
  onNew: () => void;
}) {
  const { locale, t } = useI18n();
  const [libraryView, setLibraryView] = useState<"recent" | "archived">(
    "recent",
  );
  const byNewest = (left: StoredProject, right: StoredProject) =>
    new Date(right.updatedAt).getTime() - new Date(left.updatedAt).getTime();
  const recentProjects = projects
    .filter((item) => !item.archivedAt)
    .sort(byNewest);
  const archivedProjects = projects
    .filter((item) => item.archivedAt)
    .sort(
      (left, right) =>
        new Date(right.archivedAt || right.updatedAt).getTime() -
        new Date(left.archivedAt || left.updatedAt).getTime(),
    );
  const displayedProjects =
    libraryView === "recent" ? recentProjects : archivedProjects;
  const allProjects = [...recentProjects, ...archivedProjects].sort(
    (left, right) =>
      new Date(right.updatedAt).getTime() - new Date(left.updatedAt).getTime(),
  );

  return (
    <section className="library-workspace">
      <div className="library-hero">
        <div>
          <span className="kicker">LOCAL PROJECT LIBRARY</span>
          <h2>{t("所有改编项目，都留在这台电脑。")}</h2>
          <p>
            {t("项目会自动保存。最近最多保留50个，旧项目自动归档；你也可以主动归档和恢复。")}
          </p>
        </div>
        <button className="button primary" onClick={onNew}>
          <FilePlus2 size={17} />
          {t("新建项目")}
        </button>
      </div>

      <div className="library-summary">
        <button
          type="button"
          className={`library-summary-switch ${libraryView === "recent" ? "active" : ""}`}
          aria-pressed={libraryView === "recent"}
          onClick={() => setLibraryView("recent")}
        >
          <strong>{recentProjects.length}</strong>
          <span>{t("最近项目")}</span>
        </button>
        <button
          type="button"
          className={`library-summary-switch ${libraryView === "archived" ? "active" : ""}`}
          aria-pressed={libraryView === "archived"}
          onClick={() => setLibraryView("archived")}
        >
          <strong>{archivedProjects.length}</strong>
          <span>{t("已归档")}</span>
        </button>
        <div className="library-summary-static">
          <strong>
            {allProjects.reduce(
              (total, item) => total + (item.document?.chapters.length || 0),
              0,
            )}
          </strong>
          <span>{t("累计章节")}</span>
        </div>
        <div className="library-summary-static">
          <strong>
            {allProjects.reduce(
              (total, item) => total + (item.result?.episodes.length || 0),
              0,
            )}
          </strong>
          <span>{t("已生成集数")}</span>
        </div>
      </div>

      <div className="project-library-grid" aria-live="polite">
        {displayedProjects.map((item) => {
          const current = item.id === currentProjectId;
          const archived = Boolean(item.archivedAt);
          return (
            <article
              className={`archive-card ${current ? "current" : ""} ${archived ? "archived" : ""}`}
              key={item.id}
              role="button"
              tabIndex={0}
              aria-label={t("打开项目：{{name}}", { name: item.name })}
              onClick={() => onOpen(item)}
              onKeyDown={(event) => {
                if (
                  event.target === event.currentTarget &&
                  (event.key === "Enter" || event.key === " ")
                ) {
                  event.preventDefault();
                  onOpen(item);
                }
              }}
            >
              <div className="archive-card-cap">
                <div className="archive-icon">
                  <BookOpen size={19} />
                </div>
                <span className={`archive-state phase-${item.phase}`}>
                  {archived
                    ? t("已归档")
                    : current
                      ? t("当前打开")
                      : t(item.result ? "已有成稿" : "编辑中")}
                </span>
              </div>
              <h3>{item.name}</h3>
              <p>
                {item.document
                  ? t("{{title}} · {{chapters}} 章", {
                      title: item.document.title,
                      chapters: item.document.chapters.length,
                    })
                  : t("尚未导入小说文本")}
              </p>
              <div className="archive-metrics">
                <span>
                  <b>{item.characters.length}</b>
                  {t("人物")}
                </span>
                <span>
                  <b>{item.result?.episodes.length || 0}</b>
                  {t("成稿集数")}
                </span>
                <span>
                  <b>{item.result?.quality.score || "—"}</b>
                  {t("质检")}
                </span>
              </div>
              <div className="archive-time">
                <History size={13} />
                {t("更新于 {{time}}", {
                  time: new Date(item.updatedAt).toLocaleString(
                    locale === "en-US" ? "en-US" : "zh-CN",
                    { dateStyle: "medium", timeStyle: "short" },
                  ),
                })}
              </div>
              <div className="archive-actions">
                <button
                  className="button secondary"
                  onClick={(event) => {
                    event.stopPropagation();
                    onDuplicate(item);
                  }}
                >
                  <Copy size={14} />
                  {t("复制")}
                </button>
                <button
                  className="button secondary archive-action"
                  onClick={(event) => {
                    event.stopPropagation();
                    archived ? onRestore(item) : onArchive(item);
                  }}
                >
                  {archived ? (
                    <ArchiveRestore size={14} />
                  ) : (
                    <Archive size={14} />
                  )}
                  {t(archived ? "恢复" : "归档")}
                </button>
                {archived && (
                  <button
                    className="button secondary archive-delete-action"
                    aria-label={t("永久删除项目：{{name}}", {
                      name: item.name,
                    })}
                    onClick={(event) => {
                      event.stopPropagation();
                      onDelete(item);
                    }}
                  >
                    <Trash2 size={14} />
                    {t("删除")}
                  </button>
                )}
              </div>
            </article>
          );
        })}
        {!displayedProjects.length && (
          <div className="library-empty">
            {libraryView === "recent" ? (
              <>
                <FolderKanban size={24} />
                <strong>{t("暂无最近项目")}</strong>
                <p>{t("新建项目后会显示在这里，最多保留最近50个。")}</p>
              </>
            ) : (
              <>
                <Archive size={24} />
                <strong>{t("暂无归档项目")}</strong>
                <p>{t("主动归档或超过50个的旧项目会显示在这里。")}</p>
              </>
            )}
          </div>
        )}
      </div>
    </section>
  );
}

function PromptAssetsWorkspace({
  assets,
  onUpdate,
  onReset,
}: {
  assets: PromptAsset[];
  onUpdate: (id: PromptAsset["id"], content: string) => void;
  onReset: (id: PromptAsset["id"]) => void;
}) {
  const { t } = useI18n();
  const [selectedId, setSelectedId] = useState<PromptAsset["id"]>(
    assets[0]?.id || "base",
  );
  const selected =
    assets.find((asset) => asset.id === selectedId) || assets[0];
  const impactHints: Record<PromptAsset["id"], string> = {
    base: "影响角色自动命名、章节事实抽取、故事圣经、分集规划和逐集成稿。",
    analysis: "影响原著事实、关键事件、情绪节点和制作提示的抽取结果。",
    bible: "影响人物消歧、关系、世界规则、时间线和道具生命周期。",
    outline: "影响分集核心冲突、新增信息、动态场次、转场、反转和结尾卡点。",
    episode: "影响逐集动作、对白、口语感、节拍密度、状态变化和可拍性。",
  };

  return (
    <section className="prompt-workspace">
      <div className="prompt-asset-list">
        <div className="prompt-list-heading">
          <span className="kicker">PROMPT PIPELINE</span>
          <h2>{t("管线提示词")}</h2>
          <p>{t("这里的修改会直接用于下一次在线精修改编。")}</p>
        </div>
        <div className="prompt-list">
          {assets.map((asset, index) => (
            <button
              key={asset.id}
              className={selectedId === asset.id ? "active" : ""}
              data-impact={t(impactHints[asset.id])}
              aria-label={t("{{name}}。影响范围：{{impact}}", {
                name: t(asset.name),
                impact: t(impactHints[asset.id]),
              })}
              onClick={() => setSelectedId(asset.id)}
            >
              <span>{String(index + 1).padStart(2, "0")}</span>
              <div>
                <strong>{t(asset.name)}</strong>
                <small>{t(asset.stage)}</small>
              </div>
              <ChevronDown size={14} />
            </button>
          ))}
        </div>
        <div className="prompt-safety-note">
          <ShieldCheck size={17} />
          <p>
            {t("模型调度策略由系统管理；集数、时长和质量预算由程序统一约束。")}
          </p>
        </div>
      </div>

      {selected && (
        <div className="prompt-editor">
          <div className="prompt-editor-heading">
            <div>
              <div className="prompt-stage">
                <span>{t(selected.stage)}</span>
                <span className="connected-badge">
                  <CheckCircle2 size={12} />
                  {t("已连接在线管线")}
                </span>
              </div>
              <h2>{t(selected.name)}</h2>
              <p>{t(selected.description)}</p>
            </div>
            <button
              className="button secondary"
              onClick={() => onReset(selected.id)}
            >
              <RotateCcw size={14} />
              {t("恢复默认")}
            </button>
          </div>

          <div className="prompt-editor-body">
            <div className="prompt-editor-cap">
              <span>{t("提示词内容")}</span>
              <span>
                {t("{{count}} 字符 · 自动保存", {
                  count: selected.content.length,
                })}
              </span>
            </div>
            <textarea
              value={selected.content}
              onChange={(event) => onUpdate(selected.id, event.target.value)}
              spellCheck={false}
              aria-label={t("提示词内容")}
            />
          </div>

          <div className="prompt-usage-flow">
            <span>{t("原文章节")}</span>
            <b>→</b>
            <span>{t(selected.name)}</span>
            <b>→</b>
            <span>{t("结构化 JSON")}</span>
            <b>→</b>
            <span>{t("确定性质检")}</span>
          </div>
        </div>
      )}
    </section>
  );
}

function EmptyWorkspace({ onImport }: { onImport: () => void }) {
  const { t } = useI18n();
  return (
    <section className="empty-workspace">
      <div className="empty-copy">
        <span className="kicker">NOVEL → MICRO DRAMA</span>
        <h1>
          {t("把长篇故事，")}
          <br />
          {t("锻造成")}<span>{t("能拍的短剧。")}</span>
        </h1>
        <p>
          {t("不再把整本小说塞进一次提示词。先建立故事事实、人物圣经和改名表，再规划分集、逐集生成并自动质检。")}
        </p>
        <button className="button primary large" onClick={onImport}>
          <UploadCloud size={19} />
          {t("导入小说文本")}
        </button>
        <small>{t("支持 UTF-8 编码的 TXT / MD 文件，可直接拖入窗口")}</small>
      </div>
      <div className="empty-pipeline-card">
        <div className="card-cap">
          <span>{t("可靠的数据流")}</span>
          <span>LOCAL FIRST</span>
        </div>
        {[
          ["01", t("章节切片"), t("完整处理长文，不再截断前 8000 字")],
          ["02", t("事实与人物"), t("证据可回溯，统一维护角色与关系")],
          ["03", t("分集与成稿"), t("先规划后写作，连续性上下文逐集传递")],
          ["04", t("自动质检"), t("旧名、钩子、时长、结构和风险可量化")],
        ].map((item) => (
          <div className="dataflow-row" key={item[0]}>
            <span>{item[0]}</span>
            <div>
              <strong>{item[1]}</strong>
              <p>{item[2]}</p>
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}

function SourcePanel({
  project,
  selectedChapter,
  onSelectChapter,
  selectedChapterData,
  onImport,
}: {
  project: StoredProject;
  selectedChapter: number;
  onSelectChapter: (index: number) => void;
  selectedChapterData: StoredProject["document"] extends infer _T
    ? import("./domain").Chapter | undefined
    : never;
  onImport: () => void;
}) {
  const { t } = useI18n();
  const document = project.document!;
  return (
    <aside className="source-panel panel">
      <div className="panel-heading">
        <div>
          <span className="eyebrow">SOURCE</span>
          <h2>{t("原著章节")}</h2>
        </div>
        <button className="icon-button" onClick={onImport} title={t("替换文本")}>
          <RefreshCw size={16} />
        </button>
      </div>
      <div className="source-meta">
        <div className="file-icon">
          <FileText size={19} />
        </div>
        <div>
          <strong>{document.title}</strong>
          <span>
            {document.author !== "未知"
              ? t("作者：{{author}}", { author: document.author })
              : document.fileName}
          </span>
        </div>
      </div>
      <div className="source-stats">
        <div>
          <strong>{document.chapters.length}</strong>
          <span>{t("章节")}</span>
        </div>
        <div>
          <strong>{formatNumber(document.charCount)}</strong>
          <span>{t("字符")}</span>
        </div>
        <div>
          <strong>100%</strong>
          <span>{t("已读取")}</span>
        </div>
      </div>
      <div className="chapter-list">
        {document.chapters.map((chapter, index) => (
          <button
            key={chapter.id}
            className={selectedChapter === index ? "active" : ""}
            onClick={() => onSelectChapter(index)}
          >
            <span>{String(chapter.index).padStart(2, "0")}</span>
            <div>
              <strong>{chapter.title}</strong>
              <small>{formatNumber(chapter.charCount)} 字</small>
            </div>
            {selectedChapter === index && <ChevronDown size={14} />}
          </button>
        ))}
      </div>
      {selectedChapterData && (
        <div className="source-preview">
          <div className="preview-cap">
            <span>{t("原文预览")}</span>
            <span>{t("第 {{number}} 章", { number: selectedChapterData.index })}</span>
          </div>
          <p>{selectedChapterData.content.slice(0, 360)}</p>
          <div className="fade-out" />
        </div>
      )}
    </aside>
  );
}

function OutlineWorkspace({
  project,
  useOnline,
  settings,
  running,
  onUseOnline,
  onUpdateOptions,
  onRun,
  onOpenSettings,
}: {
  project: StoredProject;
  useOnline: boolean;
  settings: ModelSettings | null;
  running: boolean;
  onUseOnline: (value: boolean) => void;
  onUpdateOptions: (patch: Partial<AdaptationOptions>) => void;
  onRun: () => void;
  onOpenSettings: () => void;
}) {
  const { t } = useI18n();
  const result = project.result;
  const budget = runtimeBudget(project.options);
  const suggestedEpisodes = recommendedEpisodeCount(
    project.document?.charCount || 0,
    project.options.durationSeconds,
  );
  const averageSourceCharacters = Math.round(
    (project.document?.charCount || 0) / Math.max(1, project.options.episodeCount),
  );
  return (
    <div className="outline-workspace">
      <div className="brief-card">
        <div className="brief-heading">
          <div>
            <span className="eyebrow">ADAPTATION BRIEF</span>
            <h2>{t("改编规格")}</h2>
          </div>
          <span className="trend-badge">{t(project.options.trendPreset)}</span>
        </div>
        <div className="brief-grid">
          <label>
            <span>{t("目标集数")}</span>
            <div className="input-suffix">
              <input
                type="number"
                min={2}
                max={60}
                value={project.options.episodeCount}
                onChange={(event) =>
                  onUpdateOptions({
                    episodeCount: Math.max(2, Math.min(60, Number(event.target.value))),
                  })
                }
              />
              <em>{t("集")}</em>
            </div>
          </label>
          <label>
            <span>{t("单集时长")}</span>
            <select
              value={project.options.durationSeconds}
              onChange={(event) => {
                const durationSeconds = Number(event.target.value);
                onUpdateOptions({
                  durationSeconds,
                  scenesPerEpisode: recommendedScenes(durationSeconds),
                });
              }}
            >
              <option value={60}>{t("{{seconds}} 秒", { seconds: 60 })}</option>
              <option value={90}>{t("{{seconds}} 秒", { seconds: 90 })}</option>
              <option value={120}>{t("{{seconds}} 秒", { seconds: 120 })}</option>
              <option value={180}>{t("{{seconds}} 秒", { seconds: 180 })}</option>
            </select>
          </label>
          <label>
            <span>{t("创作策略")}</span>
            <select
              value={project.options.trendPreset}
              onChange={(event) =>
                onUpdateOptions({
                  trendPreset: event.target.value as AdaptationOptions["trendPreset"],
                })
              }
            >
              <option value="精品爽剧">{t("精品爽剧")}</option>
              <option value="现实共鸣">{t("现实共鸣")}</option>
              <option value="轻喜反转">{t("轻喜反转")}</option>
            </select>
          </label>
        </div>
        <div className="genre-row">
          <div>
            <span>{t("自动识别题材")}</span>
            <strong>
              {result?.genre ||
                (/系统|异能/.test(project.document?.rawText || "")
                  ? t("都市异能 · 系统逆袭 · 热血轻喜")
                  : project.options.genre)}
            </strong>
          </div>
          <div className="tag-row">
            <span>{t("强钩子")}</span>
            <span>{t("高信息密度")}</span>
            <span>{t("可拍性优先")}</span>
          </div>
        </div>
        <div className="runtime-budget">
          <div className="budget-heading">
            <div>
              <span>{t("可拍时长预算")}</span>
              <strong>
                {t("{{seconds}} 秒 · 场次按剧情自动规划", {
                  seconds: project.options.durationSeconds,
                })}
              </strong>
            </div>
            <span className="budget-ok">{t("模型自动规划")}</span>
          </div>
          <div className="budget-metrics">
            <div>
              <b>
                {budget.spokenCharacters.min}–{budget.spokenCharacters.max}
              </b>
              <span>{t("有效对白字数")}</span>
            </div>
            <div>
              <b>
                {budget.scriptCharacters.min}–{budget.scriptCharacters.max}
              </b>
              <span>{t("动作与对白总字数")}</span>
            </div>
            <div>
              <b>{budget.minDialogueLines}–{budget.maxDialogueLines}</b>
              <span>{t("对白句数")}</span>
            </div>
            <div>
              <b>{averageSourceCharacters}</b>
              <span>{t("当前原文/集")}</span>
            </div>
          </div>
          {averageSourceCharacters > budget.sourceCharactersPerEpisode && (
            <p className="coverage-warning">
              {t(
                "当前每集平均承载 {{actual}} 字原文；{{seconds}} 秒建议约 {{capacity}} 字原文/集。建议将总集数提高到约 {{episodes}} 集，避免把章节压成梗概。",
                {
                  actual: averageSourceCharacters,
                  seconds: project.options.durationSeconds,
                  capacity: budget.sourceCharactersPerEpisode,
                  episodes: suggestedEpisodes,
                },
              )}
            </p>
          )}
        </div>
      </div>

      <div className="mode-card">
        <div className="mode-heading">
          <div className={`mode-icon ${useOnline ? "online" : ""}`}>
            {useOnline ? <Cloud size={19} /> : <ShieldCheck size={19} />}
          </div>
          <div>
            <strong>{t(useOnline ? "结构化大模型管线" : "离线验收管线")}</strong>
            <span>
              {useOnline
                ? settings?.hasApiKey && settings.hasFlashModel
                  ? t("双模型协同已就绪")
                  : t("需要完成双模型配置")
                : t("无需密钥，适合流程验收与界面演示")}
            </span>
          </div>
        </div>
        <div className="segmented">
          <button className={!useOnline ? "active" : ""} onClick={() => onUseOnline(false)}>
            {t("离线验收")}
          </button>
          <button className={useOnline ? "active" : ""} onClick={() => onUseOnline(true)}>
            {t("在线精修")}
          </button>
        </div>
        {useOnline &&
          (!settings?.hasApiKey || !settings.hasFlashModel) && (
          <button className="text-button" onClick={onOpenSettings}>
            <KeyRound size={14} />
            {t("配置模型")}
          </button>
          )}
      </div>

      {result ? (
        <div className="episode-board">
          <div className="board-heading">
            <div>
              <span className="eyebrow">EPISODE MAP</span>
              <h2>{t("分集卡 · {{count}} 集", { count: result.episodes.length })}</h2>
            </div>
            <div className="score-pill">
              <CircleGauge size={16} />
              {t("质检 {{score}}", { score: result.quality.score })}
            </div>
          </div>
          <div className="episode-cards">
            {result.episodes.map((episode) => (
              <article key={episode.id}>
                <div className="episode-number">{String(episode.number).padStart(2, "0")}</div>
                <div>
                  <strong>{episode.title}</strong>
                  <p>{episode.objective}</p>
                  <span>{t("卡点 · {{hook}}", { hook: episode.endHook })}</span>
                </div>
              </article>
            ))}
          </div>
        </div>
      ) : (
        <div className="ready-card">
          <div className="ready-visual">
            <div>
              <UsersRound size={19} />
            </div>
            <span />
            <div>
              <PenLine size={19} />
            </div>
            <span />
            <div>
              <ShieldCheck size={19} />
            </div>
          </div>
          <h3>{t("角色与改编规格已就绪")}</h3>
          <p>{t("系统会自动生成角色名并允许手动修改，随后完成规划、成稿和质量校验。")}</p>
        </div>
      )}

      <div className="run-dock">
        <div>
          <span>
            {t("{{characters}} 位主要人物 · {{chapters}} 章已就绪", {
              characters: project.characters.length,
              chapters: project.document?.chapters.length || 0,
            })}
          </span>
          <small>{t("生成过程可追踪，失败不会修改原文")}</small>
        </div>
        <button className="button primary run" onClick={onRun} disabled={running}>
          {running ? <RefreshCw className="spin" size={17} /> : <Play size={17} fill="currentColor" />}
          {t(running ? "正在运行…" : result ? "重新生成" : "开始改编")}
        </button>
      </div>
    </div>
  );
}

function BibleWorkspace({ result }: { result: AdaptationResult }) {
  const { t } = useI18n();
  const bible = result.storyBible;
  if (!bible) return null;
  return (
    <div className="bible-workspace">
      <div className="bible-hero">
        <div>
          <span className="eyebrow">SERIES SOURCE OF TRUTH</span>
          <h2>{t("全剧事实圣经")}</h2>
        </div>
        <p>{bible.premise}</p>
      </div>

      <section className="bible-section">
        <div className="bible-section-heading">
          <h3>{t("人物唯一身份")}</h3>
          <span>{bible.canonicalCharacters.length}</span>
        </div>
        <div className="bible-grid">
          {bible.canonicalCharacters.map((character) => (
            <article key={character.id}>
              <strong>{character.scriptName}</strong>
              <small>{character.role}</small>
              <p>
                {t("原名/别名")}：{character.sourceNames.join("、") || "—"}
              </p>
              <p>
                {t("关系")}：{character.relationships.join("；") || "—"}
              </p>
            </article>
          ))}
        </div>
      </section>

      <section className="bible-section">
        <div className="bible-section-heading">
          <h3>{t("世界规则")}</h3>
          <span>{bible.worldRules.length}</span>
        </div>
        <div className="bible-list">
          {bible.worldRules.map((rule) => (
            <article key={rule.id}>
              <strong>{rule.subject}</strong>
              <p>{rule.fact}</p>
              <small>{t("原因")}：{rule.cause}</small>
            </article>
          ))}
        </div>
      </section>

      <section className="bible-section">
        <div className="bible-section-heading">
          <h3>{t("道具与伏笔生命周期")}</h3>
          <span>{bible.propThreads.length}</span>
        </div>
        <div className="bible-grid">
          {bible.propThreads.map((prop) => (
            <article key={prop.id}>
              <strong>{prop.name}</strong>
              <small>
                {t("第{{start}}集引入 · 第{{end}}集兑现", {
                  start: prop.introducedEpisode,
                  end: prop.payoffEpisode,
                })}
              </small>
              <p>{prop.dramaticFunction}</p>
              <p>{t("当前状态")}：{prop.currentState}</p>
            </article>
          ))}
        </div>
      </section>

      <section className="bible-section">
        <div className="bible-section-heading">
          <h3>{t("分集连续性契约")}</h3>
          <span>{result.episodes.length}</span>
        </div>
        <div className="contract-list">
          {result.episodes.map((episode) => (
            <article key={episode.id}>
              <span>{String(episode.number).padStart(2, "0")}</span>
              <div>
                <strong>{episode.contract?.dominantConflict || episode.objective}</strong>
                <p>
                  {t("新增信息")}：
                  {episode.contract?.newInformation.join("；") || "—"}
                </p>
                <small>
                  {t("承接")}：
                  {episode.contract?.transitionFromPrevious || t("首集开场")}
                </small>
              </div>
              <b>{episode.runtime?.estimatedSeconds || "—"}s</b>
            </article>
          ))}
        </div>
      </section>
    </div>
  );
}

function ScriptWorkspace({
  project,
  selectedEpisode,
  onSelectEpisode,
  episode,
  onChangeContent,
}: {
  project: StoredProject;
  selectedEpisode: number;
  onSelectEpisode: (index: number) => void;
  episode: import("./domain").Episode | undefined;
  onChangeContent: (content: string) => void;
}) {
  const { t } = useI18n();
  return (
    <div className="script-workspace">
      <div className="episode-rail">
        {project.result?.episodes.map((item, index) => (
          <button
            key={item.id}
            className={selectedEpisode === index ? "active" : ""}
            onClick={() => onSelectEpisode(index)}
          >
            <span>{String(item.number).padStart(2, "0")}</span>
            <div>
              <strong>{item.title}</strong>
              <small>{t("{{count}} 场 · 已成稿", { count: item.scenes.length })}</small>
            </div>
            <Check size={13} />
          </button>
        ))}
      </div>
      {episode && (
        <div className="editor-wrap">
          <div className="editor-heading">
            <div>
              <span>{t("第 {{number}} 集", { number: episode.number })}</span>
              <strong>{episode.title}</strong>
            </div>
            <div>
              <span>{t("{{count}} 字", { count: episode.content.replace(/\s/g, "").length })}</span>
              <span>{t("自动保存")}</span>
            </div>
          </div>
          <textarea
            value={episode.content}
            onChange={(event) => onChangeContent(event.target.value)}
            spellCheck={false}
            aria-label={t("第{{number}}集剧本编辑器", {
              number: episode.number,
            })}
          />
        </div>
      )}
    </div>
  );
}

function QualityWorkspace({ result }: { result: AdaptationResult }) {
  const { t } = useI18n();
  const gate = result.quality.gate;
  const openGateIssues =
    gate?.issues.filter((issue) => issue.status === "open") || [];
  const categoryLabels: Record<
    import("./domain").QualityIssueCategory,
    string
  > = {
    source_fidelity: "原著忠实度",
    continuity: "跨集连续性",
    character: "人物动机",
    pacing: "节奏推进",
    hook: "钩子与卡点",
    dialogue: "对白攻守",
    production: "制作可行性",
    compliance: "内容风险",
  };
  return (
    <div className="quality-workspace">
      <div className="quality-hero">
        <div className="score-ring" style={{ "--score": `${result.quality.score * 3.6}deg` } as React.CSSProperties}>
          <div>
            <strong>{result.quality.score}</strong>
            <span>/ 100</span>
          </div>
        </div>
        <div>
          <span className="eyebrow">
            {gate ? "TRUSTED QUALITY GATE" : "DETERMINISTIC QA"}
          </span>
          <h2>{t(result.quality.passed ? "达到初稿交付线" : "需要修复后再交付")}</h2>
          <p>
            {t(
              gate
                ? "程序硬指标、跨集语义审片与修复复验共同判定；正式上线前仍需人工审片。"
                : "以下检查由程序规则完成，不依赖模型自评；正式上线前仍需人工审片。",
            )}
          </p>
        </div>
      </div>
      {gate && (
        <section
          className={`trusted-gate-card ${gate.status === "passed" ? "passed" : "needs-review"}`}
        >
          <div className="trusted-gate-heading">
            <div>
              <span className="eyebrow">QUALITY LEDGER · V1</span>
              <h3>
                {t(
                  gate.status === "passed"
                    ? "可信终审已通过"
                    : "可信终审需要人工复核",
                )}
              </h3>
            </div>
            <span className="trusted-gate-status">
              {gate.status === "passed" ? (
                <CheckCircle2 size={14} />
              ) : (
                <ShieldCheck size={14} />
              )}
              {t(gate.status === "passed" ? "可交付" : "已拦截")}
            </span>
          </div>
          <div className="trusted-gate-stats">
            <div>
              <b>{gate.auditedWindows}</b>
              <span>{t("审片窗口")}</span>
            </div>
            <div>
              <b>
                {gate.acceptedRepairs}/{gate.repairAttempts}
              </b>
              <span>{t("修复采纳")}</span>
            </div>
            <div>
              <b>{gate.openIssueCount}</b>
              <span>{t("开放问题")}</span>
            </div>
            <div>
              <b>{gate.deterministicScore}</b>
              <span>{t("程序复算")}</span>
            </div>
          </div>
          {openGateIssues.length > 0 ? (
            <div className="quality-ledger">
              {openGateIssues.slice(0, 6).map((issue) => (
                <article key={`${issue.id}-${issue.episodeNumbers.join("-")}`}>
                  <span className={`severity severity-${issue.severity}`}>
                    {t(
                      issue.severity === "blocker"
                        ? "阻断"
                        : issue.severity === "major"
                          ? "重大"
                          : "轻微",
                    )}
                  </span>
                  <div>
                    <strong>
                      {t(categoryLabels[issue.category])}
                      {" · "}
                      {t("第 {{episodes}} 集", {
                        episodes: issue.episodeNumbers.join("、"),
                      })}
                    </strong>
                    <p>{issue.evidence}</p>
                    <small>
                      {t("修复建议：{{instruction}}", {
                        instruction: issue.repairInstruction,
                      })}
                    </small>
                  </div>
                </article>
              ))}
            </div>
          ) : (
            <p className="trusted-gate-clear">
              <Check size={14} />
              {t("未发现阻断交付的跨集问题。")}
            </p>
          )}
        </section>
      )}
      <div className="metric-list">
        {result.quality.metrics.map((item) => (
          <article key={item.id}>
            <div className={`metric-state ${item.level}`}>
              {item.level === "good" ? <Check size={15} /> : <ShieldCheck size={15} />}
            </div>
            <div>
              <strong>{t(item.label)}</strong>
              <p>{item.detail}</p>
            </div>
            <div className="metric-bar">
              <span style={{ width: `${item.score}%` }} />
            </div>
            <b>{item.score}</b>
          </article>
        ))}
      </div>
      <div className="warning-box">
        <ShieldCheck size={19} />
        <div>
          <strong>{t("交付提示")}</strong>
          {result.quality.warnings.map((warning) => (
            <p key={warning}>{warning}</p>
          ))}
        </div>
      </div>
    </div>
  );
}

function CharacterPanel({
  project,
  onUpdateCharacter,
  onOpenQuality,
}: {
  project: StoredProject;
  onUpdateCharacter: (id: string, patch: Partial<CharacterProfile>) => void;
  onOpenQuality: () => void;
}) {
  const { t } = useI18n();
  const result = project.result;
  return (
    <aside className="character-panel panel">
      <div className="panel-heading">
        <div>
          <span className="eyebrow">CHARACTER BIBLE</span>
          <h2>{t("人物改名表")}</h2>
        </div>
        <span className="count-badge">{project.characters.length}</span>
      </div>
      <p className="panel-intro">{t("旧名仅用于源文匹配；成稿会强制使用新名并检查残留。")}</p>
      <div className="character-table-head">
        <span>{t("原著角色")}</span>
        <span>{t("剧本新名")}</span>
      </div>
      <div className="character-list">
        {project.characters.map((character) => (
          <div className="character-row" key={character.id}>
            <div className="source-name">
              <UserRound size={14} />
              <div>
                <strong>{character.sourceName}</strong>
                <small>
                  {t("{{role}} · {{count}} 次", {
                    role: t(character.role),
                    count: character.occurrences,
                  })}
                </small>
              </div>
            </div>
            <span className="rename-arrow">→</span>
            <div className="target-name editable-model-name">
              <input
                value={character.targetName}
                onChange={(event) =>
                  onUpdateCharacter(character.id, {
                    targetName: event.target.value.replace(/\s/g, ""),
                  })
                }
                placeholder={t("等待自动命名")}
                aria-label={t("{{name}}的新名字", {
                  name: character.sourceName,
                })}
              />
              <Sparkles size={12} />
            </div>
          </div>
        ))}
      </div>
      <div className="rename-note">
        <Sparkles size={14} />
        <span>{t("系统会自动生成一次角色新名；你可以直接修改，手动姓名会被保留。")}</span>
      </div>

      <div className="right-divider" />
      <div className="mini-section-heading">
        <div>
          <span className="eyebrow">QUALITY GATE</span>
          <h3>{t("交付质量")}</h3>
        </div>
        {result && (
          <button className="text-button" onClick={onOpenQuality}>
            {t("查看全部")}
          </button>
        )}
      </div>
      {result ? (
        <div className="quality-summary">
          <div className="mini-score">
            <strong>{result.quality.score}</strong>
            <span>{t("综合分")}</span>
          </div>
          <div className="mini-metrics">
            {result.quality.metrics.slice(0, 3).map((metric) => (
              <div key={metric.id}>
                <span>{t(metric.label)}</span>
                <b>{metric.score}</b>
              </div>
            ))}
          </div>
        </div>
      ) : (
        <div className="quality-placeholder">
          <CircleGauge size={24} />
          <p>{t("成稿后自动检查人物旧名、集场结构、钩子、时长和内容风险。")}</p>
        </div>
      )}
      <div className="policy-note">
        <ShieldCheck size={15} />
        <p>{t("遵循精品化与多元题材方向；AI 辅助内容需显著标识并进行人工复核。")}</p>
      </div>
    </aside>
  );
}

function SettingsDialog({
  settings,
  onClose,
  onSaved,
}: {
  settings: ModelSettings | null;
  onClose: () => void;
  onSaved: (settings: ModelSettings) => void;
}) {
  const { t } = useI18n();
  const [form, setForm] = useState({
    protocol: settings?.protocol || ("responses" as const),
    baseUrl: settings?.baseUrl || "https://api.openai.com/v1",
    model: settings?.model || "gpt-5.6-terra",
    flashModel: settings?.flashModel || "",
    reasoningEffort: settings?.reasoningEffort || ("low" as const),
    apiKey: "",
  });
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState("");

  const save = async () => {
    if (!window.desktopAPI) {
      setMessage(t("浏览器预览不保存密钥，请在桌面应用中配置"));
      return;
    }
    try {
      setSaving(true);
      const value = await window.desktopAPI.updateSettings(form);
      onSaved(value);
    } catch (caught) {
      setMessage(caught instanceof Error ? caught.message : t("保存失败"));
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="modal-backdrop" onMouseDown={onClose}>
      <div className="settings-dialog" onMouseDown={(event) => event.stopPropagation()}>
        <div className="dialog-heading">
          <div>
            <span className="eyebrow">MODEL CONNECTION</span>
            <h2>{t("模型与安全设置")}</h2>
          </div>
          <button className="icon-button" onClick={onClose}>
            <X size={18} />
          </button>
        </div>
        <div className="security-banner">
          <ShieldCheck size={19} />
          <div>
            <strong>{t("密钥不会进入前端代码或项目文件")}</strong>
            <p>{t("Electron 主进程使用系统安全存储加密；模型调用也只从主进程发起。")}</p>
          </div>
        </div>
        <div className="settings-grid">
          <div className="settings-model-note full">
            <Sparkles size={15} />
            <span>{t("系统会自动调度两个模型，无需手动分配阶段；两者共享当前 API 连接和加密密钥。")}</span>
          </div>
          <label>
            <span>{t("接口协议")}</span>
            <select
              value={form.protocol}
              onChange={(event) =>
                setForm({ ...form, protocol: event.target.value as "responses" | "chat" })
              }
            >
              <option value="responses">{t("OpenAI Responses API（推荐）")}</option>
              <option value="chat">{t("兼容 Chat Completions")}</option>
            </select>
          </label>
          <label>
            <span>API Base URL</span>
            <input
              value={form.baseUrl}
              onChange={(event) => setForm({ ...form, baseUrl: event.target.value })}
              placeholder="https://api.openai.com/v1"
            />
          </label>
          <label>
            <span>{t("创作模型")}</span>
            <input
              value={form.model}
              onChange={(event) => setForm({ ...form, model: event.target.value })}
              placeholder="gpt-5.6-terra"
            />
          </label>
          <label>
            <span>{t("高速模型")}</span>
            <input
              value={form.flashModel}
              onChange={(event) =>
                setForm({ ...form, flashModel: event.target.value })
              }
              placeholder={t("填写第二个模型 ID")}
            />
          </label>
          <label>
            <span>{t("推理强度")}</span>
            <select
              value={form.reasoningEffort}
              onChange={(event) =>
                setForm({
                  ...form,
                  reasoningEffort: event.target.value as ModelSettings["reasoningEffort"],
                })
              }
            >
              <option value="none">{t("none · 最低延迟")}</option>
              <option value="low">{t("low · 默认")}</option>
              <option value="medium">{t("medium · 质量优先")}</option>
              <option value="high">{t("high · 高成本")}</option>
            </select>
          </label>
          <label className="full">
            <span>
              API Key{" "}
              {settings?.hasApiKey && (
                <em>{t("已保存 {{hint}}", { hint: settings.apiKeyHint })}</em>
              )}
            </span>
            <input
              type="password"
              value={form.apiKey}
              onChange={(event) => setForm({ ...form, apiKey: event.target.value })}
              placeholder={settings?.hasApiKey ? t("留空则保持现有密钥") : "sk-…"}
              autoComplete="off"
            />
          </label>
        </div>
        {message && <div className="dialog-message">{message}</div>}
        <div className="dialog-actions">
          <button className="button secondary" onClick={onClose}>
            {t("取消")}
          </button>
          <button className="button primary" onClick={save} disabled={saving}>
            {saving ? <RefreshCw className="spin" size={16} /> : <KeyRound size={16} />}
            {t("保存连接")}
          </button>
        </div>
      </div>
    </div>
  );
}

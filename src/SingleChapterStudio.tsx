import { useMemo, useState, type Dispatch, type SetStateAction } from "react";
import {
  Bot,
  Check,
  ChevronDown,
  ChevronUp,
  FileText,
  KeyRound,
  LoaderCircle,
  MessageSquareText,
  Plus,
  RefreshCw,
  Sparkles,
  Trash2,
  UserRound,
} from "lucide-react";
import type {
  CharacterProfile,
  Chapter,
  SingleChapterScriptVersion,
  StoredProject,
} from "./domain";
import {
  applyRenames,
  assertValidRenameMap,
  extractCharacters,
  isGenericCharacterName,
} from "./pipeline/characters";
import {
  CHARACTER_NAMING_SCHEMA,
  REVISION_PROMPT,
  SINGLE_CHAPTER_SCRIPT_SCHEMA,
  emptySingleChapterWorkflow,
  formatRenameMap,
  formatStoryBoard,
  normalizeSingleChapterWorkflow,
  runFixedSingleChapterPipeline,
} from "./pipeline/singleChapter";

type Locale = "zh-CN" | "en-US";

function primaryModelReady(settings: ModelSettings | null) {
  return Boolean(
    settings &&
      settings.model.trim() &&
      (settings.authMode === "none" || settings.hasApiKey),
  );
}

function chapterDocument(project: StoredProject, chapter: Chapter) {
  const document = project.document!;
  return {
    ...document,
    title: chapter.title || document.title,
    rawText: chapter.content,
    charCount: chapter.charCount,
    chapters: [chapter],
  };
}

function occurrences(text: string, value: string) {
  if (!value) return 0;
  return Math.max(1, text.split(value).length - 1);
}

export function SingleChapterStudio({
  project,
  settings,
  locale,
  onChange,
  onImport,
  onOpenSettings,
  onError,
  onNotice,
}: {
  project: StoredProject;
  settings: ModelSettings | null;
  locale: Locale;
  onChange: Dispatch<SetStateAction<StoredProject>>;
  onImport: () => void;
  onOpenSettings: () => void;
  onError: (message: string) => void;
  onNotice: (message: string) => void;
}) {
  const zh = locale === "zh-CN";
  const copy = (cn: string, en: string) => (zh ? cn : en);
  const document = project.document!;
  const workflow = normalizeSingleChapterWorkflow(
    project.singleChapterWorkflow,
    document.chapters[0]?.id,
  );
  const selectedChapter =
    document.chapters.find(
      (chapter) => chapter.id === workflow.selectedChapterId,
    ) || document.chapters[0];
  const [running, setRunning] = useState<"names" | "pipeline" | "revision" | null>(null);
  const [chatOpen, setChatOpen] = useState(true);
  const [revisionInstruction, setRevisionInstruction] = useState("");

  const updateWorkflow = (
    updater: (current: ReturnType<typeof normalizeSingleChapterWorkflow>) => ReturnType<typeof normalizeSingleChapterWorkflow>,
  ) => {
    onChange((current) => {
      const normalized = normalizeSingleChapterWorkflow(
        current.singleChapterWorkflow,
        current.document?.chapters[0]?.id,
      );
      return { ...current, singleChapterWorkflow: updater(normalized) };
    });
  };

  const versionsById = useMemo(
    () => new Map(workflow.versions.map((version) => [version.id, version])),
    [workflow.versions],
  );
  const reviewVersionId =
    workflow.comparison?.reviewVersionId || workflow.activeVersionId;
  const reviewVersion = reviewVersionId
    ? versionsById.get(reviewVersionId)
    : undefined;
  const activeVersion = workflow.activeVersionId
    ? versionsById.get(workflow.activeVersionId)
    : undefined;
  const forbiddenHits = workflow.storyBoard.forbiddenWords
    .split(/[，,、\s]+/)
    .map((word) => word.trim())
    .filter((word) => word && reviewVersion?.content.includes(word));

  const resetForChapter = (chapter: Chapter) => {
    const nextCharacters = extractCharacters(chapterDocument(project, chapter));
    onChange((current) => ({
      ...current,
      characters: nextCharacters,
      result: null,
      productionPackage: null,
      phase: "characters",
      singleChapterWorkflow: {
        ...emptySingleChapterWorkflow(chapter.id),
        storyBoard:
          current.singleChapterWorkflow?.storyBoard ||
          emptySingleChapterWorkflow().storyBoard,
      },
    }));
  };

  const changeCharacter = (
    id: string,
    patch: Partial<CharacterProfile>,
  ) => {
    onChange((current) => ({
      ...current,
      characters: current.characters.map((character) =>
        character.id === id
          ? { ...character, ...patch, locked: true, nameSource: "manual" }
          : character,
      ),
      singleChapterWorkflow: {
        ...normalizeSingleChapterWorkflow(
          current.singleChapterWorkflow,
          selectedChapter?.id,
        ),
        renameConfirmed: false,
        stage: "characters",
      },
    }));
  };

  const addCharacter = () => {
    const id = crypto.randomUUID();
    onChange((current) => ({
      ...current,
      characters: [
        ...current.characters,
        {
          id,
          sourceName: "",
          targetName: "",
          role: "主要角色",
          traits: [],
          occurrences: 1,
          locked: true,
          nameSource: "manual",
        },
      ],
      singleChapterWorkflow: {
        ...normalizeSingleChapterWorkflow(
          current.singleChapterWorkflow,
          selectedChapter?.id,
        ),
        renameConfirmed: false,
        stage: "characters",
      },
    }));
  };

  const removeCharacter = (id: string) => {
    onChange((current) => ({
      ...current,
      characters: current.characters.filter((character) => character.id !== id),
      singleChapterWorkflow: {
        ...normalizeSingleChapterWorkflow(
          current.singleChapterWorkflow,
          selectedChapter?.id,
        ),
        renameConfirmed: false,
        stage: "characters",
      },
    }));
  };

  const generateNames = async () => {
    if (!selectedChapter || !window.desktopAPI || !primaryModelReady(settings)) {
      onOpenSettings();
      return;
    }
    setRunning("names");
    onError("");
    try {
      const response = await window.desktopAPI.callStructured<{
        characters: Array<{ sourceName: string; targetName: string; role: string }>;
      }>({
        route: "primary",
        name: "single_chapter_character_names",
        instructions:
          "识别章节中的主要人物并为其生成适合短剧的新中文姓名。不要使用原名、重复名或角色1一类占位名。只返回结构化结果。",
        input: `【故事板】\n${formatStoryBoard(workflow.storyBoard)}\n\n【章节】\n${selectedChapter.content}`,
        schema: CHARACTER_NAMING_SCHEMA,
      });
      const manualBySource = new Map(
        project.characters
          .filter(
            (character) =>
              character.nameSource === "manual" &&
              character.sourceName.trim() &&
              character.targetName.trim(),
          )
          .map((character) => [character.sourceName.trim(), character]),
      );
      const generated = response.characters
        .filter(
          (character) =>
            character.sourceName.trim() &&
            character.targetName.trim() &&
            !isGenericCharacterName(character.targetName),
        )
        .map((character, index): CharacterProfile => {
          const sourceName = character.sourceName.trim();
          const manual = manualBySource.get(sourceName);
          if (manual) return manual;
          return {
            id: crypto.randomUUID(),
            sourceName,
            targetName: character.targetName.trim().replace(/\s/g, ""),
            role: character.role.trim() || (index === 0 ? "核心主角" : "主要角色"),
            traits: [],
            occurrences: occurrences(selectedChapter.content, sourceName),
            locked: false,
            nameSource: "model",
          };
        });
      if (!generated.length) throw new Error(copy("AI 未识别到主要人物", "No main characters were identified"));
      onChange((current) => ({
        ...current,
        characters: generated,
        singleChapterWorkflow: {
          ...normalizeSingleChapterWorkflow(
            current.singleChapterWorkflow,
            selectedChapter.id,
          ),
          renameConfirmed: false,
          stage: "characters",
        },
      }));
      onNotice(copy("人物新名已生成，请确认", "Character names generated. Please confirm them."));
    } catch (caught) {
      onError(caught instanceof Error ? caught.message : copy("人物命名失败", "Character naming failed"));
    } finally {
      setRunning(null);
    }
  };

  const confirmRenames = () => {
    try {
      if (!project.characters.length) {
        throw new Error(copy("请至少添加一位主要人物", "Add at least one main character"));
      }
      if (project.characters.some((character) => !character.sourceName.trim())) {
        throw new Error(copy("人物原名不能为空", "Source character names cannot be empty"));
      }
      assertValidRenameMap(project.characters);
      updateWorkflow((current) => ({
        ...current,
        renameConfirmed: true,
        stage: current.versions.length ? "review" : "ready",
      }));
      onNotice(copy("人物改名已确认", "Character renames confirmed"));
    } catch (caught) {
      onError(caught instanceof Error ? caught.message : copy("人物改名无效", "Invalid character renames"));
    }
  };

  const updateStoryBoard = (
    field: keyof typeof workflow.storyBoard,
    value: string,
    maxLength: number,
  ) => {
    updateWorkflow((current) => ({
      ...current,
      storyBoard: { ...current.storyBoard, [field]: value.slice(0, maxLength) },
    }));
  };

  const callScript = async (
    instructions: string,
    input: string,
    name: string,
  ) => {
    if (!window.desktopAPI) throw new Error(copy("仅桌面版支持模型调用", "Model calls require the desktop app"));
    const response = await window.desktopAPI.callStructured<{ script: string }>({
      route: "primary",
      instructions,
      input,
      name,
      schema: SINGLE_CHAPTER_SCRIPT_SCHEMA,
    });
    const script = response.script?.trim();
    if (!script) throw new Error(copy("模型未返回剧本", "The model returned no script"));
    return applyRenames(script, project.characters);
  };

  const runPipeline = async () => {
    if (!selectedChapter) return;
    if (!workflow.renameConfirmed) {
      onError(copy("请先确认人物改名", "Confirm character renames first"));
      return;
    }
    if (!workflow.storyBoard.worldName.trim() || !workflow.storyBoard.worldBackground.trim()) {
      onError(copy("请先填写世界设定名称和世界背景", "Complete the world name and background first"));
      return;
    }
    if (!primaryModelReady(settings)) {
      onOpenSettings();
      return;
    }
    setRunning("pipeline");
    onError("");
    try {
      const constraints = `【故事板】\n${formatStoryBoard(workflow.storyBoard)}\n\n【人物改名表】\n${formatRenameMap(project.characters)}`;
      const { firstPass, finalScript } = await runFixedSingleChapterPipeline({
        chapter: selectedChapter.content,
        constraints,
        call: callScript,
        onStage: (stage) =>
          updateWorkflow((current) => ({ ...current, stage })),
      });
      const version: SingleChapterScriptVersion = {
        id: crypto.randomUUID(),
        createdAt: new Date().toISOString(),
        content: finalScript,
        source: "generated",
      };
      updateWorkflow((current) => ({
        ...current,
        firstPass,
        stage: "review",
        versions: [...current.versions, version],
        activeVersionId: version.id,
        comparison: undefined,
        messages: [],
      }));
      onChange((current) => ({ ...current, phase: "completed" }));
      onNotice(copy("单章剧本已生成", "Single-chapter script generated"));
    } catch (caught) {
      updateWorkflow((current) => ({ ...current, stage: "failed" }));
      onError(caught instanceof Error ? caught.message : copy("剧本生成失败", "Script generation failed"));
    } finally {
      setRunning(null);
    }
  };

  const updateCurrentScript = (content: string) => {
    if (!workflow.activeVersionId || workflow.comparison) return;
    updateWorkflow((current) => ({
      ...current,
      versions: current.versions.map((version) =>
        version.id === current.activeVersionId
          ? { ...version, content, source: "manual" }
          : version,
      ),
    }));
  };

  const reviseScript = async () => {
    const instruction = revisionInstruction.trim();
    if (!instruction || !activeVersion || workflow.comparison) return;
    if (!primaryModelReady(settings)) {
      onOpenSettings();
      return;
    }
    setRunning("revision");
    onError("");
    try {
      const userMessage = {
        id: crypto.randomUUID(),
        role: "user" as const,
        content: instruction,
        createdAt: new Date().toISOString(),
      };
      const fullConversation = [...workflow.messages, userMessage]
        .map((message) => `${message.role === "user" ? "用户" : "AI"}：\n${message.content}`)
        .join("\n\n");
      const revised = await callScript(
        REVISION_PROMPT,
        `【故事板】\n${formatStoryBoard(workflow.storyBoard)}\n\n【人物改名表】\n${formatRenameMap(project.characters)}\n\n【完整对话历史】\n${fullConversation}\n\n【当前完整剧本】\n${activeVersion.content}\n\n【本次修改要求】\n${instruction}`,
        "single_chapter_revision",
      );
      const newVersion: SingleChapterScriptVersion = {
        id: crypto.randomUUID(),
        createdAt: new Date().toISOString(),
        content: revised,
        source: "ai_revision",
        instruction,
      };
      updateWorkflow((current) => ({
        ...current,
        stage: "review",
        versions: [...current.versions, newVersion],
        comparison: {
          oldVersionId: current.activeVersionId!,
          newVersionId: newVersion.id,
          reviewVersionId: newVersion.id,
        },
        messages: [
          ...current.messages,
          userMessage,
          {
            id: crypto.randomUUID(),
            role: "assistant",
            content: revised,
            createdAt: new Date().toISOString(),
            versionId: newVersion.id,
          },
        ],
      }));
      setRevisionInstruction("");
      onNotice(copy("新版已生成，请选择后继续", "A new version is ready. Choose a baseline to continue."));
    } catch (caught) {
      onError(caught instanceof Error ? caught.message : copy("剧本调整失败", "Script revision failed"));
    } finally {
      setRunning(null);
    }
  };

  const chooseComparisonVersion = () => {
    if (!workflow.comparison) return;
    updateWorkflow((current) => ({
      ...current,
      activeVersionId: current.comparison?.reviewVersionId,
      comparison: undefined,
    }));
    onNotice(copy("已选定下一轮调整基线", "Baseline selected for the next revision"));
  };

  const stages = [
    copy("人物改名", "Rename cast"),
    copy("小说初改", "First pass"),
    copy("视频化再改", "Video pass"),
    copy("审阅调整", "Review"),
  ];
  const stageIndex = workflow.versions.length
    ? 3
    : workflow.stage === "second_pass"
      ? 2
      : workflow.stage === "first_pass"
        ? 1
        : 0;

  return (
    <section className="single-chapter-studio">
      <div className="single-chapter-stepper" aria-label={copy("改编步骤", "Adaptation steps")}>
        {stages.map((label, index) => (
          <div className={`${index < stageIndex ? "done" : ""} ${index === stageIndex ? "active" : ""}`} key={label}>
            <span>{index < stageIndex ? <Check size={13} /> : index + 1}</span>
            <strong>{label}</strong>
          </div>
        ))}
      </div>

      <div className="single-chapter-grid">
        <aside className="single-source panel">
          <div className="panel-heading">
            <div><span className="eyebrow">SOURCE</span><h2>{copy("单章输入", "Single chapter")}</h2></div>
            <button className="icon-button" onClick={onImport} title={copy("替换文本", "Replace source")}><RefreshCw size={16}/></button>
          </div>
          <div className="single-source-file"><FileText size={19}/><div><strong>{document.title}</strong><span>{document.fileName}</span></div></div>
          {document.chapters.length > 1 && (
            <label className="single-chapter-select">
              <span>{copy("选择要改编的章节", "Chapter to adapt")}</span>
              <select value={selectedChapter?.id} onChange={(event) => {
                const chapter = document.chapters.find((item) => item.id === event.target.value);
                if (chapter) resetForChapter(chapter);
              }}>
                {document.chapters.map((chapter) => <option value={chapter.id} key={chapter.id}>{chapter.title}</option>)}
              </select>
            </label>
          )}
          <div className="single-source-preview">
            <strong>{selectedChapter?.title}</strong>
            <span>{selectedChapter?.charCount.toLocaleString()} {copy("字", "characters")}</span>
            <p>{selectedChapter?.content.slice(0, 700)}</p>
          </div>
        </aside>

        <main className="single-workspace panel">
          {!workflow.versions.length ? (
            <>
              <div className="single-section-heading">
                <div><span className="eyebrow">STEP 1</span><h2>{copy("确认主要人物改名", "Confirm cast renames")}</h2><p>{copy("手工姓名始终优先；确认后才能进入固定流水线。", "Manual names always win. Confirm before running the fixed pipeline.")}</p></div>
                <button className="button secondary" onClick={generateNames} disabled={Boolean(running)}>{running === "names" ? <LoaderCircle className="spin" size={15}/> : <Sparkles size={15}/>} {copy("AI 生成改名", "Generate with AI")}</button>
              </div>
              <div className="single-character-head"><span>{copy("原著人物", "Source name")}</span><span>{copy("剧本新名", "Script name")}</span><span/></div>
              <div className="single-character-list">
                {project.characters.map((character) => (
                  <div className="single-character-row" key={character.id}>
                    <label><UserRound size={14}/><input value={character.sourceName} placeholder={copy("原名", "Source name")} onChange={(event) => changeCharacter(character.id, { sourceName: event.target.value.replace(/\s/g, "") })}/></label>
                    <input value={character.targetName} placeholder={copy("新名", "New name")} onChange={(event) => changeCharacter(character.id, { targetName: event.target.value.replace(/\s/g, "") })}/>
                    <button className="icon-button danger" onClick={() => removeCharacter(character.id)} aria-label={copy("删除人物", "Remove character")}><Trash2 size={14}/></button>
                  </div>
                ))}
              </div>
              <button className="text-button add-character" onClick={addCharacter}><Plus size={14}/> {copy("添加主要人物", "Add main character")}</button>
              <div className="rename-confirm-dock">
                <div>{workflow.renameConfirmed ? <Check size={16}/> : <UserRound size={16}/>}<span>{workflow.renameConfirmed ? copy("改名已确认，可开始生成", "Renames confirmed. Ready to generate.") : copy("需要用户明确确认", "Explicit confirmation required")}</span></div>
                {!workflow.renameConfirmed ? (
                  <button className="button dark" onClick={confirmRenames}>{copy("确认人物改名", "Confirm renames")}</button>
                ) : (
                  <button className="button primary" onClick={runPipeline} disabled={Boolean(running)}>{running === "pipeline" ? <LoaderCircle className="spin" size={16}/> : <Sparkles size={16}/>} {copy("运行两步改编", "Run two-pass adaptation")}</button>
                )}
              </div>
              {running === "pipeline" && (
                <div className="pipeline-running-card"><LoaderCircle className="spin" size={18}/><div><strong>{workflow.stage === "second_pass" ? copy("正在进行第二次视频化改编", "Running video adaptation pass") : copy("正在进行第一次小说精简", "Running first novel pass")}</strong><span>{copy("两次调用固定使用同一个主模型", "Both calls use the same primary model")}</span></div></div>
              )}
            </>
          ) : (
            <div className="single-review">
              <div className="single-section-heading">
                <div><span className="eyebrow">FINAL SCRIPT</span><h2>{copy("单章剧本审阅", "Single-chapter script review")}</h2><p>{copy("可直接编辑；AI 新版产生后须选择下一轮使用的版本。", "Edit directly. After an AI revision, choose the next baseline explicitly.")}</p></div>
                <span className="version-count">{workflow.versions.length} {copy("个版本", "versions")}</span>
              </div>
              {workflow.comparison && (
                <div className="version-comparison">
                  <div className="version-toggle">
                    <button className={workflow.comparison.reviewVersionId === workflow.comparison.oldVersionId ? "active" : ""} onClick={() => updateWorkflow((current) => ({ ...current, comparison: current.comparison ? { ...current.comparison, reviewVersionId: current.comparison.oldVersionId } : undefined }))}>{copy("旧版", "Previous")}</button>
                    <button className={workflow.comparison.reviewVersionId === workflow.comparison.newVersionId ? "active" : ""} onClick={() => updateWorkflow((current) => ({ ...current, comparison: current.comparison ? { ...current.comparison, reviewVersionId: current.comparison.newVersionId } : undefined }))}>{copy("新版", "New")}</button>
                  </div>
                  <button className="button dark" onClick={chooseComparisonVersion}><Check size={15}/> {copy("以当前版本继续", "Continue with this version")}</button>
                </div>
              )}
              <div className="script-editor-meta"><span>{reviewVersion?.source === "ai_revision" ? copy("AI 调整版", "AI revision") : reviewVersion?.source === "manual" ? copy("手工编辑版", "Manual edit") : copy("流水线成稿", "Pipeline draft")}</span><span>{reviewVersion?.content.replace(/\s/g, "").length || 0} {copy("字", "characters")}</span></div>
              <textarea className="single-script-editor" value={reviewVersion?.content || ""} readOnly={Boolean(workflow.comparison)} onChange={(event) => updateCurrentScript(event.target.value)} spellCheck={false}/>
              {forbiddenHits.length > 0 && <div className="forbidden-warning">{copy("检测到禁止输出词语：", "Forbidden terms found: ")}{forbiddenHits.join("、")}</div>}
              <section className={`revision-chat ${chatOpen ? "open" : ""}`}>
                <button className="revision-chat-heading" onClick={() => setChatOpen((value) => !value)}><span><MessageSquareText size={17}/><strong>{copy("AI 剧本调整", "AI script revision")}</strong></span>{chatOpen ? <ChevronDown size={16}/> : <ChevronUp size={16}/>}</button>
                {chatOpen && (
                  <div className="revision-chat-body">
                    {workflow.comparison ? (
                      <div className="choose-version-notice"><Check size={16}/>{copy("请先在旧版和新版之间选择下一轮基线。", "Choose the previous or new version before the next revision.")}</div>
                    ) : (
                      <>
                        <textarea value={revisionInstruction} onChange={(event) => setRevisionInstruction(event.target.value)} placeholder={copy("输入修改要求，例如：加强开头冲突，删掉解释性旁白……", "Describe the revision, e.g. strengthen the opening conflict and remove explanatory narration…")}/>
                        <div className="revision-chat-actions"><span>{copy("每次发送都会返回完整新版剧本", "Every message returns a complete revised script")}</span><button className="button primary" onClick={reviseScript} disabled={!revisionInstruction.trim() || Boolean(running)}>{running === "revision" ? <LoaderCircle className="spin" size={15}/> : <Bot size={15}/>} {copy("生成调整版", "Generate revision")}</button></div>
                      </>
                    )}
                  </div>
                )}
              </section>
            </div>
          )}
        </main>

        <aside className="story-board panel">
          <div className="panel-heading"><div><span className="eyebrow">STORY BIBLE</span><h2>{copy("故事板", "Story Bible")}</h2></div></div>
          <p className="panel-intro">{copy("作为整条流水线和每次剧本调整的全局约束。", "Global constraints for the pipeline and every revision.")}</p>
          <label><span>{copy("世界设定名称", "World setting name")}</span><input value={workflow.storyBoard.worldName} maxLength={80} onChange={(event) => updateStoryBoard("worldName", event.target.value, 80)} placeholder={copy("例如：雾城纪元", "e.g. The Age of Mist")}/></label>
          <label><span>{copy("世界背景", "World background")}</span><textarea value={workflow.storyBoard.worldBackground} maxLength={3000} onChange={(event) => updateStoryBoard("worldBackground", event.target.value, 3000)} placeholder={copy("时代、地点、社会规则、人物处境……", "Era, location, social rules, character circumstances…")}/><small>{workflow.storyBoard.worldBackground.length.toLocaleString()}/3,000</small></label>
          <label><span>{copy("核心词条", "Core entries")}</span><textarea value={workflow.storyBoard.coreEntries} maxLength={200} onChange={(event) => updateStoryBoard("coreEntries", event.target.value, 200)} placeholder={copy("人物卡片、核心道具或者目标", "Character cards, key props, or goals")}/><small>{workflow.storyBoard.coreEntries.length}/200</small></label>
          <label><span>{copy("禁止输出词语", "Forbidden terms")}</span><textarea value={workflow.storyBoard.forbiddenWords} maxLength={100} onChange={(event) => updateStoryBoard("forbiddenWords", event.target.value, 100)} placeholder={copy("用逗号分隔", "Separate with commas")}/><small>{workflow.storyBoard.forbiddenWords.length}/100</small></label>
          <div className="primary-model-card"><KeyRound size={16}/><div><strong>{settings?.model || copy("尚未配置主模型", "Primary model not configured")}</strong><span>{copy("本工作流只调用主模型", "This workflow only calls the primary model")}</span></div>{!primaryModelReady(settings) && <button className="text-button" onClick={onOpenSettings}>{copy("配置", "Configure")}</button>}</div>
        </aside>
      </div>
    </section>
  );
}

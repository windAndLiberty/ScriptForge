import {
  Check,
  ChevronRight,
  CirclePause,
  Download,
  Eye,
  FileClock,
  FilePenLine,
  History,
  Play,
  RefreshCw,
  RotateCcw,
  Save,
  Send,
  ShieldAlert,
  Sparkles,
  Square,
  X,
} from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { buildCreativeExport, creativeMarkdown } from "./export";
import { DEFAULT_CREATIVE_PROMPTS, defaultPromptOverride, compileCreativePrompt } from "./prompts";
import {
  advanceRun,
  approveRun,
  cancelRun,
  createRun,
  readChapterText,
  regenerateRun,
  restoreChapterVersion,
  retryRun,
  saveManualChapter,
  setChapterCandidate,
  updateCandidateArtifact,
} from "./service";
import type {
  CreativePromptOverride,
  CreativeWorkspace,
  CreativeWorkflowId,
  WorkflowRun,
  CreativeGenerationPayload,
} from "./types";
import { buildCreativeContext, workflowDefinition, WORKFLOW_DEFINITIONS } from "./workflows";

type Locale = "zh-CN" | "en-US";

const ui = {
  "zh-CN": {
    title: "创作工坊", templates: "工作流模板", chapters: "章节", noChapters: "还没有章节，先运行卷章规划。",
    seed: "起始材料", instruction: "本次补充指令", batch: "批量章节", language: "输出语言", run: "启动工作流",
    continue: "接受并继续", editAccept: "编辑后接受", regenerate: "重新生成", stop: "停止工作流", retry: "重试当前步骤",
    context: "实际上下文", prompt: "最终提示词预览", projectRules: "项目文风、禁忌与创作规则", workflowPrompt: "工作流模板提示词",
    savePrompt: "保存提示词版本", resetPrompt: "恢复默认", artifact: "产物编辑与预览", editor: "章节编辑器", history: "历史版本",
    accept: "接受候选稿", reject: "拒绝候选稿", save: "保存正式版本", words: "字", exportMd: "导出 Markdown", exportDocx: "导出 DOCX", exportJson: "导出 JSON",
    handoff: "送入改编工坊", waitingModel: "等待模型配置", waitingApproval: "等待作者确认", idle: "尚未运行", candidate: "候选稿",
    accepted: "已接受", planned: "已规划", review: "待审核", drafting: "草稿", selected: "已选择", optionalCheck: "启用连续性验证",
    promptHint: "默认提示词为英文；你可以修改为任意语言。系统契约和 JSON Schema 保持只读。",
  },
  "en-US": {
    title: "Author Studio", templates: "Workflow Templates", chapters: "Chapters", noChapters: "No chapters yet. Run Volume & Chapter Planning first.",
    seed: "Starting material", instruction: "Run-specific instructions", batch: "Batch chapters", language: "Output language", run: "Start workflow",
    continue: "Accept & Continue", editAccept: "Edit & Accept", regenerate: "Regenerate", stop: "Stop workflow", retry: "Retry step",
    context: "Actual context", prompt: "Final prompt preview", projectRules: "Project style, prohibitions, and creative rules", workflowPrompt: "Workflow template prompt",
    savePrompt: "Save prompt version", resetPrompt: "Restore default", artifact: "Artifact editor & preview", editor: "Chapter Editor", history: "Version History",
    accept: "Accept candidate", reject: "Reject candidate", save: "Save formal version", words: "words", exportMd: "Export Markdown", exportDocx: "Export DOCX", exportJson: "Export JSON",
    handoff: "Send to Adaptation Studio", waitingModel: "Waiting for model settings", waitingApproval: "Waiting for author approval", idle: "Not started", candidate: "Candidate",
    accepted: "Accepted", planned: "Planned", review: "Review", drafting: "Draft", selected: "Selected", optionalCheck: "Enable continuity validation",
    promptHint: "Default prompts are English. You may edit them in any language. The system contract and JSON Schema remain read-only.",
  },
} as const;

const workflowZh: Record<CreativeWorkflowId, [string, string]> = {
  incubation: ["新书孵化", "把灵感整理为可执行的新书企划"],
  storyBible: ["故事圣经", "维护人物、规则、地点、势力、物品和文风"],
  outline: ["卷章规划", "生成卷级剧情弧、章卡、伏笔与回收点"],
  chapterProduction: ["章节生产", "先确认整批章卡，再顺序生产正文"],
  continuityAudit: ["连贯性审计", "审计状态、知情范围、时间线、物品与伏笔"],
  chapterPolish: ["章节精修", "精修节奏、对白、重复表达和叙事视角"],
};

function statusLabel(status: WorkflowRun["status"], locale: Locale) {
  if (locale === "en-US") return status.replace(/([A-Z])/g, " $1");
  return ({ queued: "排队", running: "运行中", waitingForModel: "等待模型", waitingForApproval: "等待确认", interrupted: "已中断", failed: "失败", completed: "完成", cancelled: "取消" } as Record<string, string>)[status];
}

export function AuthorStudio({
  projectId,
  projectName,
  workspace,
  locale,
  settings,
  onChange,
  onError,
  onNotice,
  onOpenSettings,
  onHandoff,
}: {
  projectId: string;
  projectName: string;
  workspace: CreativeWorkspace;
  locale: Locale;
  settings: ModelSettings | null;
  onChange: (workspace: CreativeWorkspace) => void;
  onError: (message: string) => void;
  onNotice: (message: string) => void;
  onOpenSettings: () => void;
  onHandoff: (text: string, name: string, workspace: CreativeWorkspace) => void;
}) {
  const l = ui[locale];
  const [workflowId, setWorkflowId] = useState<CreativeWorkflowId>("incubation");
  const [run, setRun] = useState<WorkflowRun | null>(null);
  const [seed, setSeed] = useState("");
  const [instruction, setInstruction] = useState("");
  const [batchCount, setBatchCount] = useState(1);
  const [targetWords, setTargetWords] = useState(2000);
  const [validate, setValidate] = useState(true);
  const [excludedContextIds, setExcludedContextIds] = useState<string[]>([]);
  const [working, setWorking] = useState(false);
  const [selectedChapterId, setSelectedChapterId] = useState(workspace.selectedChapterId || "");
  const [chapterText, setChapterText] = useState("");
  const [candidateText, setCandidateText] = useState("");
  const [artifactPayload, setArtifactPayload] = useState<CreativeGenerationPayload | null>(null);
  const [showHistory, setShowHistory] = useState(false);
  const [showPrompt, setShowPrompt] = useState(false);
  const [workflowPrompt, setWorkflowPrompt] = useState(DEFAULT_CREATIVE_PROMPTS[workflowId]);
  const definition = workflowDefinition(workflowId);
  const selectedChapter = workspace.chapters.find((chapter) => chapter.id === selectedChapterId);
  const showChapterEditor = Boolean(selectedChapter && ["chapterProduction", "chapterPolish"].includes(run?.workflowId || workflowId));
  const context = useMemo(() => buildCreativeContext(workspace), [workspace]);
  const hasModel = Boolean(settings?.hasApiKey && settings.hasFlashModel);

  useEffect(() => {
    const override = workspace.promptOverrides.find((item) => item.workflowId === workflowId);
    setWorkflowPrompt(override?.instruction || DEFAULT_CREATIVE_PROMPTS[workflowId]);
  }, [workflowId, workspace.promptOverrides]);

  useEffect(() => {
    if (!selectedChapter) { setChapterText(""); setCandidateText(""); return; }
    void Promise.all([
      readChapterText(projectId, selectedChapter),
      readChapterText(projectId, selectedChapter, true),
    ]).then(([accepted, candidate]) => {
      setChapterText(accepted);
      setCandidateText(candidate);
    }).catch((error) => onError(error instanceof Error ? error.message : "Unable to read chapter."));
  }, [projectId, selectedChapterId, selectedChapter?.currentVersionId, selectedChapter?.candidateVersionId]);

  useEffect(() => {
    if (!run) { setArtifactPayload(null); return; }
    const artifact = [...workspace.artifacts].reverse().find((item) => item.runId === run.id && item.kind !== "promptSnapshot");
    if (!artifact) { setArtifactPayload(null); return; }
    void window.desktopAPI!.readProjectJson<CreativeGenerationPayload>({ projectId, relativePath: artifact.contentPath })
      .then(setArtifactPayload).catch(() => setArtifactPayload(null));
  }, [projectId, run?.id, run?.updatedAt, workspace.artifacts.length]);

  useEffect(() => {
    const latest = [...workspace.runs].reverse().find((item) => item.status !== "completed" && item.status !== "cancelled");
    if (!latest || !window.desktopAPI) return;
    void window.desktopAPI.readProjectJson<WorkflowRun>({ projectId, relativePath: latest.path })
      .then(async (value) => {
        if (value.status === "running" || value.status === "queued") {
          value.status = "interrupted";
          value.error = locale === "zh-CN" ? "应用上次在工作流运行期间退出，可从当前步骤恢复。" : "The app exited during this workflow. Resume from the current step.";
          value.updatedAt = new Date().toISOString();
          await window.desktopAPI!.writeProjectJson({ projectId, category: "runs", itemId: value.id, value });
        }
        setRun(value); setWorkflowId(value.workflowId);
      })
      .catch(() => undefined);
  }, []);

  const apply = (next: CreativeWorkspace, nextRun?: WorkflowRun | null) => {
    onChange(next);
    if (nextRun !== undefined) setRun(nextRun);
  };

  const launch = async () => {
    try {
      setWorking(true); onError("");
      const selectedChapterIds = workflowId === "chapterPolish" || workflowId === "continuityAudit"
        ? (selectedChapterId ? [selectedChapterId] : []) : [];
      const created = await createRun(projectId, workspace, workflowId, {
        seed,
        instruction,
        batchCount: Math.max(1, Math.min(batchCount, 10)),
        selectedChapterIds,
        parameters: { targetWords: String(targetWords), chapterCount: String(batchCount), outputLanguage: locale === "zh-CN" ? "Simplified Chinese" : "English" },
        disabledStepIds: validate ? [] : ["validate"],
        excludedContextIds,
      });
      const advanced = await advanceRun({ projectId, ...created, outputLanguage: locale === "zh-CN" ? "Simplified Chinese" : "English", hasModel, modelId: settings?.model });
      apply(advanced.workspace, advanced.run);
      if (advanced.run.status === "waitingForModel") onOpenSettings();
    } catch (error) { onError(error instanceof Error ? error.message : "Unable to start workflow."); }
    finally { setWorking(false); }
  };

  const approve = async () => {
    if (!run) return;
    try {
      setWorking(true);
      const approved = await approveRun(projectId, workspace, run);
      const advanced = await advanceRun({ projectId, ...approved, outputLanguage: locale === "zh-CN" ? "Simplified Chinese" : "English", hasModel, modelId: settings?.model });
      apply(advanced.workspace, advanced.run);
    } catch (error) { onError(error instanceof Error ? error.message : "Approval failed."); }
    finally { setWorking(false); }
  };

  const rerun = async () => {
    if (!run) return;
    try {
      setWorking(true);
      const next = retryRun(run);
      const advanced = await advanceRun({ projectId, workspace, run: next, outputLanguage: locale === "zh-CN" ? "Simplified Chinese" : "English", hasModel, modelId: settings?.model });
      apply(advanced.workspace, advanced.run);
    } catch (error) { onError(error instanceof Error ? error.message : "Retry failed."); }
    finally { setWorking(false); }
  };

  const regenerate = async () => {
    if (!run) return;
    try {
      setWorking(true);
      const advanced = await advanceRun({ projectId, workspace, run: regenerateRun(run), outputLanguage: locale === "zh-CN" ? "Simplified Chinese" : "English", hasModel, modelId: settings?.model });
      apply(advanced.workspace, advanced.run);
    } catch (error) { onError(error instanceof Error ? error.message : "Regeneration failed."); }
    finally { setWorking(false); }
  };

  const stop = async () => {
    if (!run) return;
    const stopped = cancelRun(run);
    const next = structuredClone(workspace);
    const reference = next.runs.find((item) => item.id === stopped.id);
    if (reference) { reference.status = "cancelled"; reference.updatedAt = stopped.updatedAt; }
    await window.desktopAPI!.writeProjectJson({ projectId, category: "runs", itemId: stopped.id, value: stopped });
    apply(next, stopped);
  };

  const savePrompt = () => {
    const current = workspace.promptOverrides.find((item) => item.workflowId === workflowId) || defaultPromptOverride(workflowId);
    const next: CreativePromptOverride = {
      ...current, instruction: workflowPrompt, updatedAt: new Date().toISOString(),
      revisions: [...current.revisions, { id: crypto.randomUUID(), instruction: workflowPrompt, createdAt: new Date().toISOString() }],
    };
    apply({ ...workspace, promptOverrides: [...workspace.promptOverrides.filter((item) => item.workflowId !== workflowId), next] });
    onNotice(locale === "zh-CN" ? "提示词版本已保存" : "Prompt revision saved");
  };

  const previewPrompt = () => {
    const override = { ...(workspace.promptOverrides.find((item) => item.workflowId === workflowId) || defaultPromptOverride(workflowId)), instruction: workflowPrompt };
    return compileCreativePrompt({ workflowId, workflowOverride: override, projectInstruction: workspace.projectInstruction, runInstruction: instruction,
      variables: { seed, batchCount: String(batchCount), targetWords: String(targetWords), outputLanguage: locale === "zh-CN" ? "Simplified Chinese" : "English" }, context, excludedContextIds }).snapshot.assembledPrompt;
  };

  const acceptCandidate = async (edited = false) => {
    if (!selectedChapter) return;
    try {
      const next = edited
        ? await saveManualChapter(projectId, workspace, selectedChapter.id, candidateText)
        : await setChapterCandidate(projectId, workspace, selectedChapter.id, true);
      apply(next); setChapterText(candidateText); setCandidateText("");
    } catch (error) { onError(error instanceof Error ? error.message : "Unable to accept candidate."); }
  };

  const editArtifactAndApprove = async () => {
    if (!run || !artifactPayload) return;
    try {
      await updateCandidateArtifact(projectId, workspace, run, artifactPayload);
      await approve();
    } catch (error) { onError(error instanceof Error ? error.message : "Unable to accept edited artifact."); }
  };

  const exportProject = async (extension: "md" | "json" | "docx") => {
    try {
      const value = await buildCreativeExport(projectId, projectName, workspace);
      const path = await window.desktopAPI!.saveExport({ fileName: projectName, extension,
        content: extension === "json" ? JSON.stringify(value, null, 2) : creativeMarkdown(value), document: value });
      if (path) onNotice(path);
    } catch (error) { onError(error instanceof Error ? error.message : "Export failed."); }
  };

  const handoff = async () => {
    try {
      const value = await buildCreativeExport(projectId, projectName, workspace);
      const markdown = creativeMarkdown(value);
      const id = crypto.randomUUID();
      const sourceTextPath = await window.desktopAPI!.writeProjectText({ projectId, category: "handoffs", itemId: id, content: markdown });
      const next = { ...workspace, handoffs: [...workspace.handoffs, { id, createdAt: new Date().toISOString(), chapterVersionIds: value.chapters.map((item) => item.versionId), sourceTextPath }] };
      onHandoff(markdown, `${projectName} · Adaptation`, next);
    } catch (error) { onError(error instanceof Error ? error.message : "Handoff failed."); }
  };

  return (
    <section className="author-studio">
      <aside className="creative-left panel">
        <div className="creative-heading"><span>AUTHOR STUDIO</span><h2>{l.title}</h2></div>
        <h3>{l.templates}</h3>
        <div className="workflow-list">
          {WORKFLOW_DEFINITIONS.map((item, index) => {
            const [title, summary] = locale === "zh-CN" ? workflowZh[item.id] : [item.title, item.summary];
            return <button key={item.id} className={workflowId === item.id ? "active" : ""} onClick={() => setWorkflowId(item.id)}>
              <b>{index + 1}</b><span><strong>{title}</strong><small>{summary}</small></span><ChevronRight size={15}/>
            </button>;
          })}
        </div>
        <div className="chapter-nav-heading"><h3>{l.chapters}</h3><span>{workspace.chapters.length}</span></div>
        <div className="creative-chapters">
          {!workspace.chapters.length && <p>{l.noChapters}</p>}
          {workspace.chapters.map((chapter) => <button key={chapter.id} className={selectedChapterId === chapter.id ? "active" : ""}
            onClick={() => setSelectedChapterId(chapter.id)}><span>{chapter.number}</span><div><strong>{chapter.title}</strong><small>{(l as Record<string,string>)[chapter.status] || chapter.status}</small></div></button>)}
        </div>
      </aside>

      <main className="creative-run panel">
        <div className="creative-run-title"><div><span>WORKFLOW</span><h2>{locale === "zh-CN" ? workflowZh[workflowId][0] : definition.title}</h2></div>
          <span className={`run-status ${run?.status || "idle"}`}>{run ? statusLabel(run.status, locale) : l.idle}</span></div>
        <label><span>{l.seed}</span><textarea value={seed} onChange={(event) => setSeed(event.target.value)} rows={4}/></label>
        <label><span>{l.instruction}</span><textarea value={instruction} onChange={(event) => setInstruction(event.target.value)} rows={3}/></label>
        <div className="creative-fields">
          <label><span>{l.batch}</span><input type="number" min={1} max={10} value={batchCount} onChange={(event) => setBatchCount(Math.max(1, Math.min(10, Number(event.target.value))))}/></label>
          <label><span>{l.words}</span><input type="number" min={300} max={20000} value={targetWords} onChange={(event) => setTargetWords(Number(event.target.value))}/></label>
          <label className="check-label"><input type="checkbox" checked={validate} onChange={(event) => setValidate(event.target.checked)}/><span>{l.optionalCheck}</span></label>
        </div>
        <div className="workflow-timeline">
          {definition.steps.map((step, index) => { const state = run?.workflowId === workflowId ? run.steps[index]?.status : "pending";
            return <div key={step.id} className={state}><span>{state === "completed" ? <Check size={13}/> : index + 1}</span><div><strong>{step.title}</strong><small>{step.kind}{step.optional ? " · optional" : ""}</small></div></div>; })}
        </div>
        {run?.error && <div className="creative-error"><ShieldAlert size={16}/>{run.error}</div>}
        <div className="creative-run-actions">
          {!run || ["completed", "cancelled"].includes(run.status) ? <button className="button primary" onClick={launch} disabled={working}>{working ? <RefreshCw className="spin" size={16}/> : <Play size={16}/>} {l.run}</button> : null}
          {run?.status === "waitingForApproval" && <button className="button primary" onClick={approve} disabled={working}><Check size={16}/>{l.continue}</button>}
          {run?.status === "waitingForApproval" && <button className="button secondary" onClick={regenerate} disabled={working}><RefreshCw size={16}/>{l.regenerate}</button>}
          {run && ["failed", "interrupted", "waitingForModel"].includes(run.status) && <button className="button primary" onClick={rerun} disabled={working}><RefreshCw size={16}/>{l.retry}</button>}
          {run && !["completed", "cancelled"].includes(run.status) && <button className="button secondary" onClick={stop}><Square size={15}/>{l.stop}</button>}
        </div>

        <details className="creative-context"><summary><Eye size={15}/>{l.context}<span>{context.length - excludedContextIds.length}</span></summary>
          {context.length ? context.map((item) => <label key={item.id}><input type="checkbox" checked={!excludedContextIds.includes(item.id)} onChange={(event) => setExcludedContextIds((current) => event.target.checked ? current.filter((id) => id !== item.id) : [...current, item.id])}/><span>{item.label}</span></label>) : <p>No project context selected.</p>}
        </details>
        <details className="creative-prompt" open={showPrompt} onToggle={(event) => setShowPrompt(event.currentTarget.open)}><summary><FilePenLine size={15}/>{l.prompt}</summary>
          <p>{l.promptHint}</p><label><span>{l.workflowPrompt}</span><textarea rows={7} value={workflowPrompt} onChange={(event) => setWorkflowPrompt(event.target.value)}/></label>
          <label><span>{l.projectRules}</span><textarea rows={4} value={workspace.projectInstruction} onChange={(event) => apply({...workspace, projectInstruction: event.target.value})}/></label>
          <div className="creative-prompt-actions"><button onClick={savePrompt}><Save size={14}/>{l.savePrompt}</button><button onClick={() => setWorkflowPrompt(DEFAULT_CREATIVE_PROMPTS[workflowId])}><RotateCcw size={14}/>{l.resetPrompt}</button></div>
          {showPrompt && <pre>{previewPrompt()}</pre>}
        </details>
      </main>

      <aside className="creative-artifact panel">
        <div className="artifact-heading"><div><span>ARTIFACT</span><h2>{showChapterEditor ? l.editor : l.artifact}</h2></div>
          {showChapterEditor && <button className="icon-button" onClick={() => setShowHistory(!showHistory)} title={l.history}><History size={16}/></button>}</div>
        {showChapterEditor && selectedChapter ? <>
          <div className="chapter-meta"><strong>{selectedChapter.title}</strong><span>{selectedChapter.status}</span></div>
          {selectedChapter.candidateVersionId && <div className="candidate-editor"><div><Sparkles size={14}/><b>{l.candidate}</b></div><textarea value={candidateText} onChange={(event) => setCandidateText(event.target.value)}/>
            <small>{candidateText.trim().split(/\s+/).filter(Boolean).length} {l.words}</small><div className="candidate-actions"><button onClick={() => acceptCandidate(false)}><Check size={14}/>{l.accept}</button><button onClick={() => acceptCandidate(true)}><FilePenLine size={14}/>{l.editAccept}</button><button onClick={async () => apply(await setChapterCandidate(projectId, workspace, selectedChapter.id, false))}><X size={14}/>{l.reject}</button></div></div>}
          <textarea className="chapter-editor" value={chapterText} onChange={(event) => setChapterText(event.target.value)} placeholder="Markdown"/>
          <div className="chapter-save"><span>{chapterText.trim().split(/\s+/).filter(Boolean).length} {l.words}</span><button onClick={async () => apply(await saveManualChapter(projectId, workspace, selectedChapter.id, chapterText))}><Save size={14}/>{l.save}</button></div>
          {showHistory && <div className="version-history"><h3>{l.history}</h3>{[...selectedChapter.versions].reverse().map((version) => <button key={version.id} onClick={async () => apply(await restoreChapterVersion(projectId, workspace, selectedChapter.id, version.id))}><FileClock size={14}/><span><strong>{version.source}</strong><small>{new Date(version.createdAt).toLocaleString(locale)} · {version.wordCount}</small></span>{version.accepted && <Check size={13}/>}</button>)}</div>}
        </> : artifactPayload ? <div className="generic-artifact"><label><span>Title</span><input value={artifactPayload.title} onChange={(event) => setArtifactPayload({...artifactPayload, title: event.target.value})}/></label><label><span>Summary</span><textarea rows={4} value={artifactPayload.summary} onChange={(event) => setArtifactPayload({...artifactPayload, summary: event.target.value})}/></label><label><span>Markdown</span><textarea className="artifact-markdown" value={artifactPayload.markdown} onChange={(event) => setArtifactPayload({...artifactPayload, markdown: event.target.value})}/></label>{run?.status === "waitingForApproval" && <button className="button primary" onClick={editArtifactAndApprove}><FilePenLine size={14}/>{l.editAccept}</button>}</div> : <div className="artifact-empty"><CirclePause size={32}/><p>{locale === "zh-CN" ? "运行工作流后，候选产物会出现在这里；不会静默覆盖作者正文。" : "Run a workflow to create candidate artifacts. Author text is never silently overwritten."}</p></div>}
        <div className="creative-export"><button onClick={() => exportProject("md")}><Download size={14}/>{l.exportMd}</button><button onClick={() => exportProject("docx")}><Download size={14}/>{l.exportDocx}</button><button onClick={() => exportProject("json")}><Download size={14}/>{l.exportJson}</button><button className="handoff" onClick={handoff}><Send size={14}/>{l.handoff}</button></div>
      </aside>
    </section>
  );
}

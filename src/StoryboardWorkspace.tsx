import { Download, Image, Mic, RefreshCw, Sparkles } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import type { ProductionPackage, StoredProject } from "./domain";
import { buildOfflineStoryboard, buildOnlineStoryboard, renderStoryboardMarkdown } from "./pipeline/storyboard";
import type { PromptAsset } from "./promptAssets";

export function StoryboardWorkspace({ project, locale, settings, promptAssets, onPackage, onError, onNotice }: {
  project: StoredProject;
  locale: "zh-CN" | "en-US";
  settings: ModelSettings | null;
  promptAssets: PromptAsset[];
  onPackage: (value: ProductionPackage) => void;
  onError: (message: string) => void;
  onNotice: (message: string) => void;
}) {
  const zh = locale === "zh-CN";
  const [running, setRunning] = useState(false);
  const [progress, setProgress] = useState(0);
  const [episodeIndex, setEpisodeIndex] = useState(0);
  const [shotIndex, setShotIndex] = useState(0);
  const [mediaRunning, setMediaRunning] = useState("");
  const [keyframeUrl, setKeyframeUrl] = useState("");
  const [voiceUrl, setVoiceUrl] = useState("");
  const story = project.productionPackage?.episodes[episodeIndex];
  const shot = story?.shots[shotIndex];
  const totalShots = useMemo(() => project.productionPackage?.episodes.reduce((sum, episode) => sum + episode.shots.length, 0) || 0, [project.productionPackage]);
  useEffect(() => {
    setKeyframeUrl(""); setVoiceUrl("");
    if (shot?.keyframePath) void window.desktopAPI!.readProjectMedia({ projectId: project.id, relativePath: shot.keyframePath }).then(setKeyframeUrl).catch(() => undefined);
    if (shot?.narrationPath) void window.desktopAPI!.readProjectMedia({ projectId: project.id, relativePath: shot.narrationPath }).then(setVoiceUrl).catch(() => undefined);
  }, [project.id, shot?.id, shot?.keyframePath, shot?.narrationPath]);

  const generate = async () => {
    if (!project.result) return;
    try {
      setRunning(true); setProgress(0); onError("");
      const online = Boolean(window.desktopAPI && settings?.hasApiKey && settings.hasFlashModel);
      const value = online
        ? await buildOnlineStoryboard({ result: project.result, characters: project.characters, durationSeconds: project.options.durationSeconds, locale, promptAssets, callStructured: window.desktopAPI!.callStructured, onProgress: (done, total) => setProgress(done / total * 100) })
        : buildOfflineStoryboard(project.result, project.characters, project.options.durationSeconds);
      onPackage(value); setEpisodeIndex(0); setShotIndex(0); setProgress(100);
      onNotice(zh ? "分镜制作包已保存在本地" : "Storyboard package saved locally");
    } catch (error) { onError(error instanceof Error ? error.message : "Storyboard generation failed."); }
    finally { setRunning(false); }
  };

  const updateShotMedia = (kind: "image" | "voice", path: string) => {
    if (!project.productionPackage || !story || !shot) return;
    const value = structuredClone(project.productionPackage);
    const target = value.episodes[episodeIndex].shots[shotIndex];
    if (kind === "image") target.keyframePath = path; else target.narrationPath = path;
    onPackage(value);
  };

  const image = async () => {
    if (!shot || !story) return;
    try { setMediaRunning("image"); const path = await window.desktopAPI!.generateImage({ projectId: project.id, episodeId: String(story.episodeNumber), shotId: shot.id, prompt: `${shot.imagePrompt}\nAvoid: ${shot.negativePrompt}` }); updateShotMedia("image", path); onNotice(zh ? "首帧图片已保存到项目" : "Keyframe image saved to the project"); }
    catch (error) { onError(error instanceof Error ? error.message : "Image generation failed."); } finally { setMediaRunning(""); }
  };
  const voice = async () => {
    if (!shot || !story) return;
    const text = shot.narration || shot.dialogue;
    if (!text) { onError(zh ? "当前镜头没有可合成的旁白或台词" : "This shot has no narration or dialogue to synthesize."); return; }
    try { setMediaRunning("voice"); const path = await window.desktopAPI!.synthesizeSpeech({ projectId: project.id, episodeId: String(story.episodeNumber), shotId: shot.id, text }); updateShotMedia("voice", path); onNotice(zh ? "语音已保存到项目" : "Voice audio saved to the project"); }
    catch (error) { onError(error instanceof Error ? error.message : "Speech generation failed."); } finally { setMediaRunning(""); }
  };
  const exportValue = async () => {
    if (!project.productionPackage) return;
    const path = await window.desktopAPI!.saveExport({ fileName: `${project.name} · Storyboard`, extension: "md", content: renderStoryboardMarkdown(project.productionPackage, project.name) });
    if (path) onNotice(path);
  };

  if (!project.productionPackage) return <div className="storyboard-empty"><Sparkles size={34}/><h2>{zh ? "尚未生成分镜" : "No storyboard generated"}</h2><p>{zh ? "离线模式也可生成完整文本分镜；图片与配音按需使用 BYOK 模型。" : "Offline mode can generate the complete text storyboard. Images and voice use optional BYOK models."}</p><button className="button primary" onClick={generate} disabled={running}>{running ? <RefreshCw className="spin" size={16}/> : <Sparkles size={16}/>} {zh ? "生成分镜" : "Generate Storyboard"}</button></div>;

  return <section className="storyboard-workspace">
    <div className="storyboard-summary"><div><span>PRODUCTION PACKAGE</span><h2>{zh ? "分镜制作包" : "Storyboard Production Package"}</h2></div><div><b>{totalShots}</b><small>{zh ? "镜头" : "shots"}</small></div><button className="button secondary" onClick={generate} disabled={running}><RefreshCw className={running ? "spin" : ""} size={15}/>{zh ? "重新生成" : "Regenerate"}</button><button className="button secondary" onClick={exportValue}><Download size={15}/>{zh ? "导出分镜" : "Export"}</button></div>
    {running && <div className="storyboard-progress"><span style={{width: `${progress}%`}}/></div>}
    <div className="storyboard-grid"><aside><h3>{zh ? "分集" : "EPISODES"}</h3>{project.productionPackage.episodes.map((episode, index) => <button key={episode.episodeNumber} className={episodeIndex === index ? "active" : ""} onClick={() => {setEpisodeIndex(index); setShotIndex(0);}}><b>EP {episode.episodeNumber}</b><span>{episode.title}</span><small>{episode.shots.length} {zh ? "镜" : "shots"}</small></button>)}</aside>
      <aside><h3>{zh ? "镜头" : "SHOTS"}</h3>{story?.shots.map((item, index) => <button key={item.id} className={shotIndex === index ? "active" : ""} onClick={() => setShotIndex(index)}><b>{item.number}</b><span>{item.title}</span><small>{item.durationSeconds.toFixed(1)}s</small></button>)}</aside>
      <main>{shot && <><div className="shot-heading"><div><span>SHOT {shot.number}</span><h2>{shot.title}</h2></div><b>{shot.durationSeconds.toFixed(1)}s</b></div><div className="shot-tags"><span>{shot.shotSize}</span><span>{shot.cameraMovement}</span><span>9:16</span></div>
        {[[zh?"构图":"Composition",shot.composition],[zh?"画面动作":"Visual action",shot.visualAction],[zh?"台词":"Dialogue",shot.dialogue],[zh?"旁白":"Narration",shot.narration],[zh?"声音":"Sound",shot.soundEffects],[zh?"连续性":"Continuity",shot.continuityNotes],[zh?"制作备注":"Production notes",shot.productionNotes],[zh?"首帧提示词":"Keyframe prompt",shot.imagePrompt],[zh?"反向提示词":"Negative prompt",shot.negativePrompt]].filter(([,value])=>value).map(([label,value])=><div className="shot-detail" key={label}><h3>{label}</h3><p>{value}</p></div>)}
        <div className="media-actions"><button onClick={image} disabled={mediaRunning === "image" || !settings?.imageModel}><Image size={15}/>{mediaRunning === "image" ? (zh?"生成中":"Generating") : (zh?"生成首帧":"Generate Keyframe")}</button><button onClick={voice} disabled={mediaRunning === "voice" || !settings?.speechModel}><Mic size={15}/>{mediaRunning === "voice" ? (zh?"生成中":"Generating") : (zh?"生成语音":"Generate Voice")}</button></div>
        {(shot.keyframePath || shot.narrationPath) && <div className="media-preview">{keyframeUrl && <img src={keyframeUrl} alt={`${shot.title} keyframe`}/>} {voiceUrl && <audio src={voiceUrl} controls/>}<div className="media-paths">{shot.keyframePath && <span>{zh?"图片":"Image"}: {shot.keyframePath}</span>}{shot.narrationPath && <span>{zh?"语音":"Voice"}: {shot.narrationPath}</span>}</div></div>}
      </>}</main></div>
  </section>;
}

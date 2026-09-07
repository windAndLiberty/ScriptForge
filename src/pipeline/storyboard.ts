import type {
  AdaptationResult,
  CharacterProfile,
  Episode,
  EpisodeStoryboard,
  ProductionPackage,
  ScriptScene,
  StoryboardShot,
} from "../domain";
import { promptContent, type PromptAsset } from "../promptAssets";

const negativePrompt = "landscape framing, text watermark, subtitles, logo, malformed fingers, extra limbs, distorted face, inconsistent character appearance, low resolution";

export const storyboardSchema = {
  type: "object", additionalProperties: false, required: ["visualStyle", "characterVisualAnchors", "shots"],
  properties: {
    visualStyle: { type: "string" }, characterVisualAnchors: { type: "array", items: { type: "string" } },
    shots: { type: "array", minItems: 1, items: { type: "object", additionalProperties: false,
      required: ["sceneId", "title", "durationSeconds", "shotSize", "cameraMovement", "composition", "visualAction", "dialogue", "narration", "soundEffects", "imagePrompt", "negativePrompt", "continuityNotes", "productionNotes"],
      properties: { sceneId: { type: "string" }, title: { type: "string" }, durationSeconds: { type: "number", minimum: .5, maximum: 15 }, shotSize: { type: "string" }, cameraMovement: { type: "string" }, composition: { type: "string" }, visualAction: { type: "string" }, dialogue: { type: "string" }, narration: { type: "string" }, soundEffects: { type: "string" }, imagePrompt: { type: "string" }, negativePrompt: { type: "string" }, continuityNotes: { type: "string" }, productionNotes: { type: "string" } } } },
  },
} as const;

interface EpisodeResponse { visualStyle: string; characterVisualAnchors: string[]; shots: Omit<StoryboardShot, "id" | "number">[]; }

function anchors(characters: CharacterProfile[], text: string) {
  const matched = characters.filter((character) => text.includes(character.targetName) || text.includes(character.sourceName));
  return (matched.length ? matched : characters).slice(0, 12).map((character) =>
    `${character.targetName}: role=${character.role}; stable identifying traits=${character.traits.slice(0, 4).join(", ") || "appearance appropriate to the role"}; keep facial structure, hairstyle, and primary costume colors consistent.`);
}

function prompt(scene: ScriptScene, beat: string, visualAnchors: string[]) {
  return `Opening keyframe for a vertical micro-drama, 9:16, location: ${scene.location}, action beat: ${beat}, cinematic realistic lighting, clear facial expressions, ${visualAnchors.join("; ")}`;
}

function normalizeDurations(values: number[], target: number) {
  const safe = values.map((value) => Math.max(.5, Math.min(15, value || 3)));
  const sum = safe.reduce((total, value) => total + value, 0) || 1;
  const result = safe.map((value) => Math.round((value / sum * target) * 2) / 2);
  result[result.length - 1] += target - result.reduce((total, value) => total + value, 0);
  return result;
}

function makeEpisode(episode: Episode, response: EpisodeResponse, durationSeconds: number): EpisodeStoryboard {
  const values = response.shots.filter((shot) => shot.visualAction.trim());
  const source = values.length ? values : [{ sceneId: episode.scenes[0]?.id || "scene-1", title: episode.title, durationSeconds: 1, shotSize: "Medium", cameraMovement: "Locked", composition: "9:16 subject composition", visualAction: episode.openingHook, dialogue: "", narration: "", soundEffects: "Production sound", imagePrompt: `Vertical micro-drama, 9:16, ${episode.openingHook}, cinematic realistic lighting`, negativePrompt, continuityNotes: "Maintain character, prop, and screen-direction continuity", productionNotes: "Director review required" }];
  const durations = normalizeDurations(source.map((shot) => shot.durationSeconds), durationSeconds);
  return { episodeNumber: episode.number, title: episode.title, aspectRatio: "9:16", visualStyle: response.visualStyle || "Cinematic realistic vertical micro-drama", characterVisualAnchors: response.characterVisualAnchors,
    shots: source.map((shot, index) => ({ ...shot, id: `ep${episode.number}-shot-${index + 1}`, number: index + 1, durationSeconds: durations[index], sceneId: episode.scenes.some((scene) => scene.id === shot.sceneId) ? shot.sceneId : episode.scenes[0]?.id || "scene-1" })) };
}

export function buildOfflineStoryboard(result: AdaptationResult, characters: CharacterProfile[], durationSeconds: number): ProductionPackage {
  return { version: "storyboard-v1", createdAt: new Date().toISOString(), mode: "offline", episodes: result.episodes.map((episode) => {
    const episodeAnchors = anchors(characters, episode.content);
    const shots: EpisodeResponse["shots"] = episode.scenes.flatMap((scene) => {
      const sceneAnchors = anchors(characters, `${scene.heading}\n${scene.action}\n${scene.dialogue.map((line) => `${line.speaker} ${line.text}`).join("\n")}`);
      return [{ sceneId: scene.id, title: scene.heading, durationSeconds: 4, shotSize: "Medium", cameraMovement: "Slow push-in", composition: "9:16 centered subject with foreground depth", visualAction: scene.action, dialogue: "", narration: "", soundEffects: "Ambient and synchronous action sound", imagePrompt: prompt(scene, scene.action, sceneAnchors), negativePrompt, continuityNotes: "Maintain wardrobe, prop positions, lighting direction, and screen direction", productionNotes: "Prioritize shootable action and readable performance" },
        ...scene.dialogue.map((line) => ({ sceneId: scene.id, title: `${line.speaker} reaction`, durationSeconds: 3, shotSize: "Close-up", cameraMovement: "Locked or subtle push-in", composition: "Eyes on the upper third of the vertical frame", visualAction: `${line.speaker} delivers the line with a clear reaction.`, dialogue: `${line.speaker}: ${line.text}`, narration: "", soundEffects: "Breath, clothing, and production sound", imagePrompt: prompt(scene, `${line.speaker} says: ${line.text}`, sceneAnchors), negativePrompt, continuityNotes: "Match eyeline, axis, and action with the previous shot", productionNotes: "Keep dialogue concise and let reaction lead the cut" }))];
    });
    return makeEpisode(episode, { visualStyle: "Cinematic realistic vertical micro-drama with performance-first lighting", characterVisualAnchors: episodeAnchors, shots }, durationSeconds);
  }) };
}

export async function buildOnlineStoryboard(args: { result: AdaptationResult; characters: CharacterProfile[]; durationSeconds: number; locale: "zh-CN" | "en-US"; promptAssets?: PromptAsset[]; callStructured: DesktopAPI["callStructured"]; onProgress?: (completed: number, total: number) => void; }) {
  const episodes: EpisodeStoryboard[] = [];
  for (const [index, episode] of args.result.episodes.entries()) {
    const visualAnchors = anchors(args.characters, episode.content);
    const response = await args.callStructured<EpisodeResponse>({
      instructions: `You are a storyboard director and line producer. ${promptContent(args.promptAssets, "storyboard")} Write production fields in ${args.locale === "zh-CN" ? "Simplified Chinese" : "English"}; always write imagePrompt and negativePrompt in English.`,
      input: `[Fixed Format] 9:16 vertical frame; target duration: ${args.durationSeconds} seconds.\n[Stable Character Visual Anchors]\n${visualAnchors.join("\n")}\n[Episode Contract] Objective: ${episode.objective}; reversal: ${episode.reversal}; ending: ${episode.endHook}\n[Approved Screenplay]\n${episode.content}`,
      name: `episode_${episode.number}_storyboard`, schema: storyboardSchema as unknown as Record<string, unknown>, route: "primary",
    });
    episodes.push(makeEpisode(episode, response, args.durationSeconds)); args.onProgress?.(index + 1, args.result.episodes.length);
  }
  return { version: "storyboard-v1", createdAt: new Date().toISOString(), mode: "online", episodes } satisfies ProductionPackage;
}

export function renderStoryboardMarkdown(value: ProductionPackage, projectName: string) {
  const lines = [`# ${projectName} · Storyboard Production Package`, "", `- Version: ${value.version}`, `- Mode: ${value.mode}`, `- Total shots: ${value.episodes.reduce((total, item) => total + item.shots.length, 0)}`, "- AI-assisted storyboards require director, cinematography, art, sound, and production review.", ""];
  value.episodes.forEach((episode) => { lines.push(`## EP ${episode.episodeNumber} · ${episode.title}`, "", `Format: ${episode.aspectRatio} · ${episode.visualStyle} · ${episode.shots.reduce((total, shot) => total + shot.durationSeconds, 0).toFixed(1)}s`, "", "Character visual anchors:", ...episode.characterVisualAnchors.map((item) => `- ${item}`), ""); episode.shots.forEach((shot) => lines.push(`### ${shot.number}. ${shot.title} (${shot.durationSeconds.toFixed(1)}s)`, "", `- Shot / movement: ${shot.shotSize} · ${shot.cameraMovement}`, `- Composition: ${shot.composition}`, `- Visual action: ${shot.visualAction}`, shot.dialogue ? `- Dialogue: ${shot.dialogue}` : "", shot.narration ? `- Narration: ${shot.narration}` : "", `- Sound: ${shot.soundEffects}`, `- Continuity: ${shot.continuityNotes}`, `- Production: ${shot.productionNotes}`, `- Keyframe prompt: ${shot.imagePrompt}`, `- Negative prompt: ${shot.negativePrompt}`, "")); });
  return lines.filter((line, index, all) => line || all[index - 1] !== "").join("\n");
}

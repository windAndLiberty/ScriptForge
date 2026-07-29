import type {
  AdaptationOptions,
  AdaptationResult,
  Chapter,
  CharacterProfile,
  DialogueLine,
  Episode,
  ScriptScene,
} from "../domain";
import { applyRenames, assertValidRenameMap } from "./characters";
import { groupChapters } from "./ingest";
import { evaluateScript } from "./quality";

function cleanLine(line: string) {
  return line
    .replace(/^[“”"「」『』]+|[“”"「」『』]+$/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

function shortenDialogue(value: string, maximumCharacters = 15) {
  const cleaned = cleanLine(value);
  let readable = 0;
  let result = "";
  for (const character of Array.from(cleaned)) {
    if (/[\p{L}\p{N}]/u.test(character)) readable += 1;
    if (readable > maximumCharacters) break;
    result += character;
  }
  return readable > maximumCharacters ? `${result.replace(/[，,：:；;]$/, "")}…` : result;
}

function quotedPassages(text: string) {
  const matches = [...text.matchAll(/[“「『"]([^”」』"\n]{2,100})[”」』"]/g)]
    .map((match) => ({
      text: cleanLine(match[1]),
      index: match.index ?? 0,
    }))
    .filter((item) => item.text.length >= 2 && item.text.length <= 100);
  return matches;
}

function actionPassages(text: string) {
  return text
    .split("\n")
    .map(cleanLine)
    .filter(
      (line) =>
        line.length >= 12 &&
        line.length <= 110 &&
        !/^[\[【（(]/.test(line) &&
        !/[“”「」『』"]/.test(line) &&
        !/^第.+章/.test(line),
    );
}

function inferLocation(text: string) {
  const choices: Array<[RegExp, string, string]> = [
    [/夜市|地摊/, "夜·外", "江城夜市"],
    [/医院|病房|急诊/, "日·内", "医院"],
    [/教室|学校|一中/, "日·内", "教室"],
    [/家里|客厅|卧室|公寓/, "夜·内", "住所"],
    [/商场|店里|超市/, "日·内", "商场"],
    [/街|路边|巷/, "日·外", "街道"],
  ];
  return choices.find(([pattern]) => pattern.test(text))?.slice(1) as
    | [string, string]
    | undefined;
}

function inferSpeaker(
  source: string,
  quoteIndex: number,
  characters: CharacterProfile[],
  fallbackIndex: number,
) {
  let nearest:
    | { character: CharacterProfile; distance: number }
    | undefined;
  characters.forEach((character) => {
    let cursor = source.indexOf(
      character.sourceName,
      Math.max(0, quoteIndex - 260),
    );
    while (cursor >= 0 && cursor <= quoteIndex + 260) {
      const distance = Math.abs(cursor - quoteIndex);
      if (!nearest || distance < nearest.distance) {
        nearest = { character, distance };
      }
      cursor = source.indexOf(
        character.sourceName,
        cursor + character.sourceName.length,
      );
    }
  });
  return (
    nearest?.character.targetName ||
    characters[Math.min(fallbackIndex, 1) % Math.max(1, characters.length)]
      ?.targetName ||
    "人物"
  );
}

function buildDialogue(
  source: string,
  characters: CharacterProfile[],
  offset: number,
): DialogueLine[] {
  const focusedCharacters = characters.slice(0, 4);
  const quotes = quotedPassages(source).slice(offset, offset + 4);
  const dialogue = quotes.map((quote, index) => ({
      speaker: inferSpeaker(
        source,
        quote.index,
        focusedCharacters,
        index + offset,
      ),
      text: shortenDialogue(applyRenames(quote.text, characters)),
    }));
  const protagonist = characters[0]?.targetName || "主角";
  const opponent = characters[1]?.targetName || "对手";
  const fallbacks = [
    { speaker: protagonist, text: "想让我认输？这才刚刚开始。" },
    { speaker: opponent, text: "你拿什么翻盘？" },
    { speaker: protagonist, text: "就拿你最看不起的这一步。" },
    { speaker: opponent, text: "那就让我看看你的底牌。" },
  ];
  const normalized = dialogue.map((line, index) =>
    (line.text.match(/[\p{L}\p{N}]/gu)?.length || 0) < 9
      ? fallbacks[index % fallbacks.length]
      : line,
  );
  while (normalized.length < 4) {
    normalized.push(fallbacks[normalized.length]);
  }
  return normalized.slice(0, 4);
}

function sceneSource(group: Chapter[], sceneIndex: number, sceneCount: number) {
  const combined = group.map((chapter) => chapter.content).join("\n");
  const size = Math.ceil(combined.length / sceneCount);
  return combined.slice(sceneIndex * size, (sceneIndex + 1) * size);
}

function buildScene(
  group: Chapter[],
  characters: CharacterProfile[],
  sceneIndex: number,
  sceneCount: number,
): ScriptScene {
  const source = sceneSource(group, sceneIndex, sceneCount);
  const [heading, location] = inferLocation(source) || [
    sceneIndex === 0 ? "日·外" : "日·内",
    sceneIndex === 0 ? "城市街区" : "临时场所",
  ];
  const actions = actionPassages(source);
  const selectedAction =
    actions[sceneIndex % Math.max(actions.length, 1)] ||
    "局面骤然变化，众人的目光同时落在主角身上。";
  const performanceBeats = [
    "人群迅速围拢，对手横身挡住去路。主角握紧手里的证据，反逼一步。",
    "对手抬手施压，旁人立刻噤声。主角没有后退，突然换了一种做法。",
    "现场骤然安静，关键物件落在地上。主角抢先按住，局面当场逆转。",
  ];
  return {
    id: `scene-${sceneIndex + 1}`,
    heading,
    location,
    action: `${applyRenames(selectedAction, characters)}${performanceBeats[sceneIndex % performanceBeats.length]}`,
    dialogue: buildDialogue(source, characters, sceneIndex * 3),
  };
}

export function renderEpisode(episode: Episode, durationSeconds?: number) {
  const lines = [
    `第${episode.number}集《${episode.title}》${durationSeconds ? `（约${durationSeconds}秒）` : ""}`,
    "",
  ];
  episode.scenes.forEach((scene, index) => {
    lines.push(`${index + 1}. ${scene.heading} ${scene.location}`);
    lines.push(`△ ${scene.action}`);
    scene.dialogue.forEach((line) => {
      lines.push(`${line.speaker}：${line.text}`);
    });
    lines.push("");
  });
  return lines.join("\n");
}

function episodeTitle(group: Chapter[], index: number) {
  const sourceTitle = group[0]?.title || `命运转折 ${index + 1}`;
  return sourceTitle
    .replace(/[？?！!]+$/g, "")
    .replace(/^是你么[:：]?/, "")
    .slice(0, 16);
}

function firstOrFallback(values: string[], fallback: string) {
  return values.find((value) => value.length >= 4) || fallback;
}

export function buildOfflineAdaptation(
  document: import("../domain").NovelDocument,
  characters: CharacterProfile[],
  options: AdaptationOptions,
): AdaptationResult {
  assertValidRenameMap(characters);
  const groups = groupChapters(document.chapters, options.episodeCount);
  const protagonist = characters[0]?.targetName || "主角";
  const episodes: Episode[] = groups.map((group, index) => {
    const source = group.map((chapter) => chapter.content).join("\n");
    const quotes = quotedPassages(source).map((item) =>
      applyRenames(item.text, characters),
    );
    const actions = actionPassages(source).map((item) =>
      applyRenames(item, characters),
    );
    const scenes = Array.from(
      { length: options.scenesPerEpisode },
      (_, sceneIndex) =>
        buildScene(
          group,
          characters,
          sceneIndex,
          options.scenesPerEpisode,
        ),
    );
    const episode: Episode = {
      id: `episode-${index + 1}`,
      number: index + 1,
      title: episodeTitle(group, index),
      sourceChapterIds: group.map((chapter) => chapter.id),
      plannedSceneCount: options.scenesPerEpisode,
      openingHook: firstOrFallback(
        quotes,
        `${protagonist}被逼到退无可退，异变在此刻发生。`,
      ),
      objective: firstOrFallback(
        actions,
        `${protagonist}必须在公开冲突中夺回主动权。`,
      ),
      reversal: firstOrFallback(
        quotes.slice(2),
        `所有人以为${protagonist}已经落败，他却亮出意想不到的底牌。`,
      ),
      endHook: firstOrFallback(
        [...quotes].reverse(),
        `更强的对手现身，直指${protagonist}刚刚得到的秘密。`,
      ),
      scenes,
      content: "",
    };
    episode.content = renderEpisode(episode, options.durationSeconds);
    return episode;
  });

  const genre = /系统|异能|觉醒|灵气/.test(document.rawText)
    ? "都市异能·系统逆袭·热血轻喜"
    : options.genre;
  const sourceFacts = document.chapters.slice(0, 5).map((chapter) => {
    const action = actionPassages(chapter.content)[0] || chapter.content.slice(0, 60);
    return `第${chapter.index}章：${applyRenames(action, characters)}`;
  });
  const result: AdaptationResult = {
    logline: `${protagonist}从人生低谷意外获得改变命运的能力，在一次次公开冲突中用机敏和行动完成逆袭，却也被卷入更大的危机。`,
    genre,
    themes: ["尊严与生存", "小人物逆袭", "能力与代价", "轻喜反转"],
    sourceFacts,
    episodes,
    quality: {
      score: 0,
      metrics: [],
      warnings: [],
      passed: false,
    },
    generatedAt: new Date().toISOString(),
    mode: "offline",
  };
  result.quality = evaluateScript(episodes, characters, options);
  return result;
}

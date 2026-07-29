import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import type { AdaptationOptions } from "../src/domain";
import { extractCharacters } from "../src/pipeline/characters";
import { parseNovelText } from "../src/pipeline/ingest";
import { buildOfflineAdaptation } from "../src/pipeline/offline";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(scriptDir, "..");

function invariant(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(`验收失败：${message}`);
}

const fixtureArgument =
  process.argv[2] || process.env.SCRIPTFORGE_ACCEPTANCE_FIXTURE;
invariant(
  fixtureArgument,
  "请传入验收文本路径：npm run acceptance -- <path-to-novel.txt>",
);

const fixturePath = path.resolve(fixtureArgument);
const outputDir = path.join(projectRoot, "acceptance");

invariant(fs.existsSync(fixturePath), `找不到附件：${fixturePath}`);
const source = fs.readFileSync(fixturePath, "utf8");
const document = parseNovelText(source, path.basename(fixturePath));
const characters = extractCharacters(document, 8);
const options: AdaptationOptions = {
  episodeCount: 8,
  durationSeconds: 60,
  scenesPerEpisode: 3,
  genre: "都市逆袭·热血轻喜",
  tone: "高燃、机敏、轻喜",
  trendPreset: "精品爽剧",
};
const result = buildOfflineAdaptation(document, characters, options);
const scriptText = result.episodes.map((episode) => episode.content).join("\n\n");

invariant(document.title === "开局地摊卖大力", "未正确识别作品标题");
invariant(
  document.chapters.length === 10,
  `章节数应为10，实际为${document.chapters.length}`,
);
invariant(document.charCount > 20_000, "未读取完整的1-10章文本");
invariant(characters.length >= 6, "主要人物识别数量不足");
invariant(
  ["江南", "夏瑶", "钟映雪", "王林", "李慕言"].every((name) =>
    characters.some((character) => character.sourceName === name),
  ),
  "关键人物识别不完整",
);
invariant(
  new Set(characters.map((character) => character.targetName)).size ===
    characters.length,
  "人物新名存在重复",
);
invariant(
  characters.every((character) => !scriptText.includes(character.sourceName)),
  "剧本中仍有旧名残留",
);
invariant(result.episodes.length === 8, "未按目标生成8集");
invariant(
  result.episodes.every(
    (episode) =>
      episode.scenes.length === options.scenesPerEpisode &&
      episode.openingHook.length > 0 &&
      episode.endHook.length > 0 &&
      episode.scenes.every((scene) => scene.dialogue.length >= 3),
  ),
  "分集、场次、对白或钩子结构不完整",
);
invariant(
  result.quality.metrics.some((metric) => metric.id === "completeness"),
  "未执行新版成稿完整度检查",
);

fs.mkdirSync(outputDir, { recursive: true });
const report = {
  fixture: fixturePath,
  runAt: new Date().toISOString(),
  document: {
    title: document.title,
    author: document.author,
    charCount: document.charCount,
    chapterCount: document.chapters.length,
  },
  characterMap: characters.map((character) => ({
    source: character.sourceName,
    target: character.targetName,
    occurrences: character.occurrences,
  })),
  result: {
    structuralPassed: true,
    episodeCount: result.episodes.length,
    sceneCount: result.episodes.reduce(
      (total, episode) => total + episode.scenes.length,
      0,
    ),
    qualityScore: result.quality.score,
    qualityPassed: result.quality.passed,
    qualityMetrics: result.quality.metrics,
    qualityWarnings: result.quality.warnings,
    oldNameLeaks: characters.filter((character) =>
      scriptText.includes(character.sourceName),
    ),
  },
};
fs.writeFileSync(
  path.join(outputDir, "report.json"),
  JSON.stringify(report, null, 2),
  "utf8",
);
fs.writeFileSync(
  path.join(outputDir, "开局地摊卖大力_短剧验收稿.txt"),
  [
    "《开局地摊卖大力·短剧改编验收稿》",
    `题材：${result.genre}`,
    `一句话梗概：${result.logline}`,
    "说明：本文件由无密钥离线验收管线生成，用于验证数据流、改名、分集、编辑与导出；正式成稿建议切换在线精修。",
    "",
    scriptText,
  ].join("\n"),
  "utf8",
);

console.log(JSON.stringify(report, null, 2));
console.log(`\nPASS：附件已通过验收，报告位于 ${path.join(outputDir, "report.json")}`);

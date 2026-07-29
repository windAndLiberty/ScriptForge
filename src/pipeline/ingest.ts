import type { Chapter, NovelDocument } from "../domain";

const CHAPTER_HEADING =
  /^第\s*([0-9一二三四五六七八九十百零两〇]+)\s*章(?:\s+|[:：]?)(.*)$/gm;

function compactCount(text: string) {
  return text.replace(/\s/g, "").length;
}

function cleanChapterContent(content: string) {
  return content
    .replace(/^-{5,}\s*$/gm, "")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

export function parseNovelText(
  rawText: string,
  fileName = "未命名小说.txt",
): NovelDocument {
  const normalized = rawText
    .replace(/^\uFEFF/, "")
    .replace(/\r\n?/g, "\n")
    .trim();
  if (!normalized) throw new Error("文件内容为空");

  const matches = [...normalized.matchAll(CHAPTER_HEADING)];
  const metadata = matches.length ? normalized.slice(0, matches[0].index) : "";
  const title =
    metadata.match(/《([^》]+)》/)?.[1]?.trim() ||
    fileName.replace(/\.[^.]+$/, "").replace(/[_-]\d.*$/, "") ||
    "未命名小说";
  const author =
    metadata.match(/(?:作者|作\s*者)\s*[:：]\s*([^\n]+)/)?.[1]?.trim() || "未知";
  const intro =
    metadata.match(/(?:简介|内容简介)\s*[:：]\s*([\s\S]*?)(?=\n(?:来源|状态)\s*[:：]|={5,}|$)/)?.[1]?.trim() ||
    "";

  let chapters: Chapter[];
  if (!matches.length) {
    chapters = [
      {
        id: "chapter-1",
        index: 1,
        title: "正文",
        content: normalized,
        charCount: compactCount(normalized),
      },
    ];
  } else {
    chapters = matches.map((match, position) => {
      const start = (match.index ?? 0) + match[0].length;
      const end = matches[position + 1]?.index ?? normalized.length;
      const content = cleanChapterContent(normalized.slice(start, end));
      const numeric = Number(match[1]);
      return {
        id: `chapter-${position + 1}`,
        index: Number.isFinite(numeric) ? numeric : position + 1,
        title: match[2]?.trim() || `第${position + 1}章`,
        content,
        charCount: compactCount(content),
      };
    });
  }

  return {
    fileName,
    title,
    author,
    intro,
    rawText: normalized,
    charCount: compactCount(normalized),
    chapters,
  };
}

export function groupChapters(chapters: Chapter[], targetGroups: number) {
  const groups: Chapter[][] = [];
  const count = Math.max(1, Math.min(targetGroups, chapters.length));
  for (let index = 0; index < count; index += 1) {
    const from = Math.floor((index * chapters.length) / count);
    const to = Math.floor(((index + 1) * chapters.length) / count);
    groups.push(chapters.slice(from, Math.max(from + 1, to)));
  }
  return groups;
}

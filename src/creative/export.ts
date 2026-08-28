import type { CreativeWorkspace, VolumeOutline } from "./types";

export interface CreativeExportChapter {
  number: number;
  volumeNumber: number;
  volumeTitle: string;
  title: string;
  heading: string;
  content: string;
  versionId: string;
}

export interface CreativeProjectExport {
  schemaVersion: 1;
  projectName: string;
  brief: CreativeWorkspace["briefs"][number] | null;
  storyBible: CreativeWorkspace["storyBibles"][number] | null;
  outlines: VolumeOutline[];
  chapters: CreativeExportChapter[];
  characterStates: CreativeWorkspace["characterStates"];
  timeline: CreativeWorkspace["timeline"];
  foreshadowing: CreativeWorkspace["foreshadowing"];
  exportedAt: string;
}

export async function buildCreativeExport(
  projectId: string,
  projectName: string,
  workspace: CreativeWorkspace,
  chapterIds?: Set<string>,
): Promise<CreativeProjectExport> {
  const selected = workspace.chapters
    .filter((chapter) => !chapterIds || chapterIds.has(chapter.id))
    .filter((chapter) => chapter.status === "accepted" && chapter.currentVersionId)
    .sort((a, b) => a.number - b.number);
  const chapters: CreativeExportChapter[] = [];
  for (const chapter of selected) {
    const version = chapter.versions.find((item) => item.id === chapter.currentVersionId && item.accepted);
    if (!version) continue;
    const content = await window.desktopAPI!.readProjectText({ projectId, relativePath: version.contentPath });
    const outline = workspace.outlines.find((item) => item.number === chapter.volumeNumber);
    chapters.push({
      number: chapter.number,
      volumeNumber: chapter.volumeNumber,
      volumeTitle: outline?.title || `Volume ${chapter.volumeNumber}`,
      title: chapter.title,
      heading: `Chapter ${chapter.number}: ${chapter.title}`,
      content,
      versionId: version.id,
    });
  }
  if (!chapters.length) throw new Error("There are no accepted chapters to export.");
  return {
    schemaVersion: 1,
    projectName,
    brief: workspace.briefs.find((item) => item.id === workspace.activeBriefId) || null,
    storyBible: workspace.storyBibles.find((item) => item.id === workspace.activeStoryBibleId) || null,
    outlines: workspace.outlines,
    chapters,
    characterStates: workspace.characterStates,
    timeline: workspace.timeline,
    foreshadowing: workspace.foreshadowing,
    exportedAt: new Date().toISOString(),
  };
}

export function creativeMarkdown(value: CreativeProjectExport) {
  const lines = [`# ${value.projectName}`, ""];
  let volume: number | undefined;
  for (const chapter of value.chapters) {
    if (chapter.volumeNumber !== volume) {
      lines.push(`## ${chapter.volumeTitle}`, "");
      volume = chapter.volumeNumber;
    }
    lines.push(`### ${chapter.heading}`, "", chapter.content, "");
  }
  return lines.join("\n");
}

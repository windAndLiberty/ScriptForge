import type {
  BookAnalysisCharacter,
  BookAnalysisHighlightCategory,
  BookAnalysisReport,
  BookAnalysisResult,
  BookAnalysisTechnique,
  BookAnalysisVersion,
  CharacterProfile,
  NovelDocument,
} from "../domain";
import { callModelStage, type StructuredCaller } from "./modelRouter";

export interface BookAnalysisProgress {
  stage:
    | "preparing"
    | "extracting"
    | "compressing"
    | "analyzing"
    | "validating"
    | "done";
  completed: number;
  total: number;
  percent: number;
  message: string;
}

export interface BookAnalysisChunk {
  id: string;
  label: string;
  chapterIds: string[];
  content: string;
  charCount: number;
}

interface ChunkEvidence {
  chapterIds: string[];
  summary: string;
  plotBeats: string[];
  characterMoves: string[];
  hooks: string[];
  highlights: string[];
  foreshadowing: string[];
  styleSignals: string[];
  uncertainties: string[];
}

interface EvidenceDigest {
  coverageChapterIds: string[];
  storyArc: string;
  plotBeats: string[];
  characters: string[];
  hooks: string[];
  highlights: string[];
  foreshadowing: string[];
  styleSignals: string[];
  uncertainties: string[];
}

type StructureSection = BookAnalysisReport["structure"];
type CharacterSection = BookAnalysisReport["characters"];
type CommercialSections = Pick<
  BookAnalysisReport,
  "title" | "meta" | "highlights" | "style" | "learning"
>;

const stringArray = {
  type: "array",
  items: { type: "string" },
};

const evidenceArray = {
  type: "array",
  items: { type: "string" },
};

const techniqueSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    name: { type: "string" },
    observation: { type: "string" },
    reusableMethod: { type: "string" },
    evidenceChapterIds: evidenceArray,
  },
  required: [
    "name",
    "observation",
    "reusableMethod",
    "evidenceChapterIds",
  ],
};

const characterSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    name: { type: "string" },
    identity: { type: "string" },
    narrativeFunction: { type: "string" },
    motivation: { type: "string" },
    arc: { type: "string" },
    relationships: stringArray,
    evidenceChapterIds: evidenceArray,
  },
  required: [
    "name",
    "identity",
    "narrativeFunction",
    "motivation",
    "arc",
    "relationships",
    "evidenceChapterIds",
  ],
};

const highlightCategorySchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    type: { type: "string" },
    intensity: { type: "string" },
    mechanism: { type: "string" },
    representativeScenes: stringArray,
    evidenceChapterIds: evidenceArray,
  },
  required: [
    "type",
    "intensity",
    "mechanism",
    "representativeScenes",
    "evidenceChapterIds",
  ],
};

const structureSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    classification: { type: "string" },
    openingHook: { type: "string" },
    rhythmOverview: { type: "string" },
    phases: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          name: { type: "string" },
          chapterRange: { type: "string" },
          rhythm: { type: "string" },
          description: { type: "string" },
          highlightDensity: { type: "string" },
          evidenceChapterIds: evidenceArray,
        },
        required: [
          "name",
          "chapterRange",
          "rhythm",
          "description",
          "highlightDensity",
          "evidenceChapterIds",
        ],
      },
    },
    foreshadowing: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          content: { type: "string" },
          planted: { type: "string" },
          revealed: { type: "string" },
          quality: { type: "string" },
          evidenceChapterIds: evidenceArray,
        },
        required: [
          "content",
          "planted",
          "revealed",
          "quality",
          "evidenceChapterIds",
        ],
      },
    },
    strengths: stringArray,
    risks: stringArray,
  },
  required: [
    "classification",
    "openingHook",
    "rhythmOverview",
    "phases",
    "foreshadowing",
    "strengths",
    "risks",
  ],
};

const characterSectionSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    protagonist: characterSchema,
    antagonists: { type: "array", items: characterSchema },
    supporting: { type: "array", items: characterSchema },
    relationshipOverview: { type: "string" },
    evaluation: { type: "string" },
  },
  required: [
    "protagonist",
    "antagonists",
    "supporting",
    "relationshipOverview",
    "evaluation",
  ],
};

const commercialSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    title: { type: "string" },
    meta: {
      type: "object",
      additionalProperties: false,
      properties: {
        sourceTitle: { type: "string" },
        author: { type: "string" },
        charCount: { type: "integer", minimum: 0 },
        chapterCount: { type: "integer", minimum: 1 },
        genreTags: stringArray,
        logline: { type: "string" },
        targetReader: { type: "string" },
        summary: { type: "string" },
      },
      required: [
        "sourceTitle",
        "author",
        "charCount",
        "chapterCount",
        "genreTags",
        "logline",
        "targetReader",
        "summary",
      ],
    },
    highlights: {
      type: "object",
      additionalProperties: false,
      properties: {
        overview: { type: "string" },
        categories: {
          type: "array",
          items: highlightCategorySchema,
        },
        peakZone: { type: "string" },
        droughtZone: { type: "string" },
        averageInterval: { type: "string" },
        signatureMoments: stringArray,
        strengths: stringArray,
        risks: stringArray,
      },
      required: [
        "overview",
        "categories",
        "peakZone",
        "droughtZone",
        "averageInterval",
        "signatureMoments",
        "strengths",
        "risks",
      ],
    },
    style: {
      type: "object",
      additionalProperties: false,
      properties: {
        language: { type: "string" },
        narration: { type: "string" },
        sceneWriting: { type: "string" },
        dialogue: { type: "string" },
        emotionalControl: { type: "string" },
        techniques: { type: "array", items: techniqueSchema },
      },
      required: [
        "language",
        "narration",
        "sceneWriting",
        "dialogue",
        "emotionalControl",
        "techniques",
      ],
    },
    learning: {
      type: "object",
      additionalProperties: false,
      properties: {
        techniques: { type: "array", items: techniqueSchema },
        structureBlueprint: stringArray,
        imitationDirections: stringArray,
        pitfalls: stringArray,
        score: { type: "integer", minimum: 0, maximum: 10 },
        recommendation: { type: "string" },
      },
      required: [
        "techniques",
        "structureBlueprint",
        "imitationDirections",
        "pitfalls",
        "score",
        "recommendation",
      ],
    },
  },
  required: ["title", "meta", "highlights", "style", "learning"],
};

const reportSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    title: { type: "string" },
    meta: commercialSchema.properties.meta,
    structure: structureSchema,
    characters: characterSectionSchema,
    highlights: commercialSchema.properties.highlights,
    style: commercialSchema.properties.style,
    learning: commercialSchema.properties.learning,
  },
  required: [
    "title",
    "meta",
    "structure",
    "characters",
    "highlights",
    "style",
    "learning",
  ],
};

const chunkEvidenceSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    chapterIds: evidenceArray,
    summary: { type: "string" },
    plotBeats: stringArray,
    characterMoves: stringArray,
    hooks: stringArray,
    highlights: stringArray,
    foreshadowing: stringArray,
    styleSignals: stringArray,
    uncertainties: stringArray,
  },
  required: [
    "chapterIds",
    "summary",
    "plotBeats",
    "characterMoves",
    "hooks",
    "highlights",
    "foreshadowing",
    "styleSignals",
    "uncertainties",
  ],
};

const digestSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    coverageChapterIds: evidenceArray,
    storyArc: { type: "string" },
    plotBeats: stringArray,
    characters: stringArray,
    hooks: stringArray,
    highlights: stringArray,
    foreshadowing: stringArray,
    styleSignals: stringArray,
    uncertainties: stringArray,
  },
  required: [
    "coverageChapterIds",
    "storyArc",
    "plotBeats",
    "characters",
    "hooks",
    "highlights",
    "foreshadowing",
    "styleSignals",
    "uncertainties",
  ],
};

function compactCount(text: string) {
  return text.replace(/\s/g, "").length;
}

function splitLongText(text: string, maxChars: number) {
  const parts: string[] = [];
  let remaining = text.trim();
  while (remaining.length > maxChars) {
    const minimum = Math.floor(maxChars * 0.55);
    const candidates = [
      remaining.lastIndexOf("\n", maxChars),
      remaining.lastIndexOf("。", maxChars),
      remaining.lastIndexOf("！", maxChars),
      remaining.lastIndexOf("？", maxChars),
      remaining.lastIndexOf("；", maxChars),
    ].filter((position) => position >= minimum);
    const splitAt = candidates.length ? Math.max(...candidates) + 1 : maxChars;
    parts.push(remaining.slice(0, splitAt).trim());
    remaining = remaining.slice(splitAt).trim();
  }
  if (remaining) parts.push(remaining);
  return parts;
}

export function chunkNovelForBookAnalysis(
  document: NovelDocument,
  maxChars = 7600,
): BookAnalysisChunk[] {
  const chunks: BookAnalysisChunk[] = [];
  let buffer: Array<{ chapterId: string; label: string; content: string }> = [];
  let bufferLength = 0;

  const flush = () => {
    if (!buffer.length) return;
    const chapterIds = [...new Set(buffer.map((item) => item.chapterId))];
    const content = buffer
      .map((item) => `【${item.label}】\n${item.content}`)
      .join("\n\n");
    chunks.push({
      id: `book-chunk-${chunks.length + 1}`,
      label: buffer.map((item) => item.label).join(" / "),
      chapterIds,
      content,
      charCount: compactCount(content),
    });
    buffer = [];
    bufferLength = 0;
  };

  for (const chapter of document.chapters) {
    const segments = splitLongText(chapter.content, maxChars);
    for (let index = 0; index < segments.length; index += 1) {
      const segment = segments[index];
      const label =
        segments.length === 1
          ? `第${chapter.index}章 ${chapter.title}`
          : `第${chapter.index}章 ${chapter.title}（${index + 1}/${segments.length}）`;
      if (bufferLength && bufferLength + segment.length > maxChars) flush();
      buffer.push({ chapterId: chapter.id, label, content: segment });
      bufferLength += segment.length;
      if (bufferLength >= maxChars * 0.9) flush();
    }
  }
  flush();

  if (!chunks.length && document.rawText.trim()) {
    return splitLongText(document.rawText, maxChars).map((content, index) => ({
      id: `book-chunk-${index + 1}`,
      label: `正文（${index + 1}）`,
      chapterIds: document.chapters.map((chapter) => chapter.id),
      content,
      charCount: compactCount(content),
    }));
  }
  return chunks;
}

async function mapConcurrent<T, R>(
  items: T[],
  concurrency: number,
  worker: (item: T, index: number) => Promise<R>,
) {
  const results = new Array<R>(items.length);
  let nextIndex = 0;
  const workers = Array.from(
    { length: Math.max(1, Math.min(concurrency, items.length)) },
    async () => {
      while (nextIndex < items.length) {
        const index = nextIndex;
        nextIndex += 1;
        results[index] = await worker(items[index], index);
      }
    },
  );
  await Promise.all(workers);
  return results;
}

function evidenceToDigest(evidence: ChunkEvidence): EvidenceDigest {
  return {
    coverageChapterIds: evidence.chapterIds,
    storyArc: evidence.summary,
    plotBeats: evidence.plotBeats,
    characters: evidence.characterMoves,
    hooks: evidence.hooks,
    highlights: evidence.highlights,
    foreshadowing: evidence.foreshadowing,
    styleSignals: evidence.styleSignals,
    uncertainties: evidence.uncertainties,
  };
}

function groupItems<T>(items: T[], size: number) {
  const groups: T[][] = [];
  for (let index = 0; index < items.length; index += size) {
    groups.push(items.slice(index, index + size));
  }
  return groups;
}

function sourceContext(document: NovelDocument) {
  return {
    sourceTitle: document.title,
    author: document.author,
    charCount: document.charCount,
    chapterCount: document.chapters.length,
    chapterIndex: document.chapters.map((chapter) => ({
      id: chapter.id,
      index: chapter.index,
      title: chapter.title,
    })),
  };
}

function normalizeEvidenceIds(
  report: BookAnalysisReport,
  document: NovelDocument,
) {
  const valid = new Set(document.chapters.map((chapter) => chapter.id));
  const clean = (ids: string[]) => [...new Set(ids.filter((id) => valid.has(id)))];
  report.structure.phases.forEach((item) => {
    item.evidenceChapterIds = clean(item.evidenceChapterIds);
  });
  report.structure.foreshadowing.forEach((item) => {
    item.evidenceChapterIds = clean(item.evidenceChapterIds);
  });
  [
    report.characters.protagonist,
    ...report.characters.antagonists,
    ...report.characters.supporting,
  ].forEach((item) => {
    item.evidenceChapterIds = clean(item.evidenceChapterIds);
  });
  report.highlights.categories.forEach((item) => {
    item.evidenceChapterIds = clean(item.evidenceChapterIds);
  });
  [...report.style.techniques, ...report.learning.techniques].forEach((item) => {
    item.evidenceChapterIds = clean(item.evidenceChapterIds);
  });
}

export function validateBookAnalysisReport(
  report: BookAnalysisReport,
  document: NovelDocument,
) {
  const warnings: string[] = [];
  if (!report.meta.summary.trim()) warnings.push("书籍梗概为空");
  if (!report.structure.phases.length) warnings.push("缺少节奏阶段分析");
  if (!report.characters.protagonist.name.trim()) warnings.push("未识别主角");
  if (!report.highlights.categories.length) warnings.push("缺少爽点分类");
  if (!report.style.techniques.length) warnings.push("缺少文风证据");
  if (!report.learning.techniques.length) warnings.push("缺少可复用技法");

  const referenced = new Set<string>();
  const collect = (ids: string[]) => ids.forEach((id) => referenced.add(id));
  report.structure.phases.forEach((item) => collect(item.evidenceChapterIds));
  report.structure.foreshadowing.forEach((item) =>
    collect(item.evidenceChapterIds),
  );
  [
    report.characters.protagonist,
    ...report.characters.antagonists,
    ...report.characters.supporting,
  ].forEach((item) => collect(item.evidenceChapterIds));
  report.highlights.categories.forEach((item) =>
    collect(item.evidenceChapterIds),
  );
  [...report.style.techniques, ...report.learning.techniques].forEach((item) =>
    collect(item.evidenceChapterIds),
  );
  if (document.chapters.length > 1 && referenced.size < 2) {
    warnings.push("报告中的章节证据覆盖偏少，建议人工复核");
  }
  return warnings;
}

function createInitialVersion(report: BookAnalysisReport): BookAnalysisVersion {
  return {
    id: crypto.randomUUID(),
    instruction: "初始拆书报告",
    createdAt: new Date().toISOString(),
    report,
  };
}

export async function runOnlineBookAnalysis(params: {
  document: NovelDocument;
  characters: CharacterProfile[];
  outputLanguage?: "Simplified Chinese" | "English";
  callStructured: StructuredCaller;
  onProgress?: (progress: BookAnalysisProgress) => void;
}): Promise<BookAnalysisResult> {
  const { document, characters, callStructured, onProgress } = params;
  const outputLanguage = params.outputLanguage || "Simplified Chinese";
  const chunks = chunkNovelForBookAnalysis(document);
  onProgress?.({
    stage: "preparing",
    completed: 0,
    total: chunks.length,
    percent: 3,
    message: `已按叙事边界切分为 ${chunks.length} 个证据块`,
  });

  let extracted = 0;
  const evidence = await mapConcurrent(chunks, 3, async (chunk) => {
    const result = await callModelStage<ChunkEvidence>(
      callStructured,
      "book_analysis_extract",
      {
        instructions: `You are a long-form fiction evidence analyst. Analyze only the current evidence block and never infer the ending of the entire book.
Extract event causality, character-state changes, reader hooks, payoff mechanisms, foreshadowing, and prose-style signals.
Every judgment must trace to a supplied chapterId. Put uncertain information in uncertainties and never invent an event absent from the source.
Write every natural-language field in ${outputLanguage}. Be specific and avoid unsupported boilerplate praise.`,
        input: `[Evidence Block] ${chunk.id}
[Chapter IDs] ${chunk.chapterIds.join(", ")}
[Chapter Range] ${chunk.label}
[Source Text]
${chunk.content}`,
        name: "book_analysis_extract",
        schema: chunkEvidenceSchema,
      },
    );
    extracted += 1;
    onProgress?.({
      stage: "extracting",
      completed: extracted,
      total: chunks.length,
      percent: 5 + Math.round((extracted / Math.max(1, chunks.length)) * 50),
      message: `正在覆盖全书证据：${extracted}/${chunks.length}`,
    });
    return {
      ...result,
      chapterIds: chunk.chapterIds,
    };
  });

  let digests: EvidenceDigest[];
  if (evidence.length > 8) {
    const batches = groupItems(evidence, 7);
    let compressed = 0;
    digests = await mapConcurrent(batches, 2, async (batch) => {
      const digest = await callModelStage<EvidenceDigest>(
        callStructured,
        "book_analysis_digest",
        {
          instructions: `You are an evidence-compression editor. Compress consecutive evidence blocks into one digest for specialist analysis.
Preserve event causality, character changes, hooks, payoff patterns, foreshadowing, prose signals, and uncertainties. Never rewrite uncertainty as fact.
coverageChapterIds must contain every chapter ID in the input. Write every natural-language field in ${outputLanguage}.`,
          input: JSON.stringify(batch),
          name: "book_analysis_digest",
          schema: digestSchema,
        },
      );
      compressed += 1;
      onProgress?.({
        stage: "compressing",
        completed: compressed,
        total: batches.length,
        percent: 56 + Math.round((compressed / batches.length) * 12),
        message: `正在建立全书分层证据：${compressed}/${batches.length}`,
      });
      return digest;
    });
  } else {
    digests = evidence.map(evidenceToDigest);
  }

  const context = JSON.stringify({
    source: sourceContext(document),
    knownCharacters: characters.map((character) => ({
      name: character.sourceName,
      role: character.role,
      traits: character.traits,
      occurrences: character.occurrences,
    })),
    evidenceDigests: digests,
  });
  let analyzedSections = 0;
  const markSection = (name: string) => {
    analyzedSections += 1;
    onProgress?.({
      stage: "analyzing",
      completed: analyzedSections,
      total: 3,
      percent: 69 + analyzedSections * 7,
      message: `${name}完成，正在交叉汇总`,
    });
  };

  const [structure, characterSection, commercial] = await Promise.all([
    callModelStage<StructureSection>(
      callStructured,
      "book_analysis_structure",
      {
        instructions: `You are a senior long-form fiction structure editor. Use the layered full-book evidence to analyze the opening hook, structural type, buildup-to-payoff cycles, pacing gaps, and foreshadowing payoffs.
Every phase and foreshadowing record must cite real chapter-* evidence IDs. Clearly distinguish confirmed evidence from unresolved setup; never repackage a summary as evaluation.
Write every natural-language field in ${outputLanguage}. Identify learnable strengths as well as padding, repetition, and logic risks.`,
        input: context,
        name: "book_analysis_structure",
        schema: structureSchema,
      },
    ).then((value) => {
      markSection("叙事结构分析");
      return value;
    }),
    callModelStage<CharacterSection>(
      callStructured,
      "book_analysis_characters",
      {
        instructions: `You are a character-system editor for long-form fiction. Use evidence to identify the protagonist's drive, growth arc, special ability or its source, antagonist tiers, supporting-character functions, and relationship changes.
Use source character names rather than adaptation names. Never split one person into several or merge distinct people because their roles look similar.
Every core character must cite chapter-* evidence IDs. Write every natural-language field in ${outputLanguage}.`,
        input: context,
        name: "book_analysis_characters",
        schema: characterSectionSchema,
      },
    ).then((value) => {
      markSection("人物体系分析");
      return value;
    }),
    callModelStage<CommercialSections>(
      callStructured,
      "book_analysis_commercial",
      {
        instructions: `You are an editor specializing in commercial appeal, prose style, and transferable writing methods. Use evidence to complete book metadata, payoff analysis, style analysis, and learning recommendations.
Prefer the original book title; derive one only when it is missing. Explain payoff through setup, trigger, release, and aftermath. Every style judgment must cite chapter-* evidence IDs.
Recommendations may reuse methods but never copy characters, settings, or distinctive wording. The score must be an integer from 0 to 10. Write every natural-language field in ${outputLanguage}.`,
        input: context,
        name: "book_analysis_commercial",
        schema: commercialSchema,
      },
    ).then((value) => {
      markSection("爽点、文风与学习建议");
      return value;
    }),
  ]);

  const report: BookAnalysisReport = {
    ...commercial,
    title: commercial.title.trim() || document.title,
    meta: {
      ...commercial.meta,
      sourceTitle: document.title,
      author: document.author,
      charCount: document.charCount,
      chapterCount: document.chapters.length,
    },
    structure,
    characters: characterSection,
  };

  onProgress?.({
    stage: "validating",
    completed: 1,
    total: 1,
    percent: 94,
    message: "正在核对章节证据与报告完整度",
  });
  normalizeEvidenceIds(report, document);
  const warnings = validateBookAnalysisReport(report, document);
  const version = createInitialVersion(report);
  onProgress?.({
    stage: "done",
    completed: chunks.length,
    total: chunks.length,
    percent: 100,
    message: "一键拆书完成",
  });
  return {
    report,
    versions: [version],
    currentVersion: 0,
    generatedAt: new Date().toISOString(),
    mode: "online",
    totalChunks: chunks.length,
    analyzedChunks: chunks.length,
    coveragePercent: 100,
    warnings,
    outputLanguage,
  };
}

function fallbackCharacter(
  character: CharacterProfile | undefined,
  document: NovelDocument,
): BookAnalysisCharacter {
  return {
    name: character?.sourceName || "待模型识别",
    identity: character?.role || "核心人物",
    narrativeFunction: "承担主要视角与冲突推进",
    motivation: "需结合全书证据进一步确认",
    arc: `在《${document.title}》现有章节中持续推进核心目标`,
    relationships: [],
    evidenceChapterIds: document.chapters.slice(0, 3).map((item) => item.id),
  };
}

function keywordCount(text: string, pattern: RegExp) {
  return text.match(pattern)?.length || 0;
}

function offlineTechnique(
  name: string,
  observation: string,
  reusableMethod: string,
  chapterIds: string[],
): BookAnalysisTechnique {
  return { name, observation, reusableMethod, evidenceChapterIds: chapterIds };
}

export function buildOfflineBookAnalysis(
  document: NovelDocument,
  characters: CharacterProfile[],
): BookAnalysisResult {
  const chapters = document.chapters;
  const chunks = chunkNovelForBookAnalysis(document);
  const chapterIds = chapters.map((chapter) => chapter.id);
  const openingIds = chapterIds.slice(0, Math.min(3, chapterIds.length));
  const phaseCount = Math.min(4, Math.max(1, Math.ceil(chapters.length / 3)));
  const phases = Array.from({ length: phaseCount }, (_, index) => {
    const from = Math.floor((index * chapters.length) / phaseCount);
    const to = Math.max(
      from + 1,
      Math.floor(((index + 1) * chapters.length) / phaseCount),
    );
    const group = chapters.slice(from, to);
    return {
      name: index === 0 ? "开篇建局" : index === phaseCount - 1 ? "阶段收束" : `冲突推进${index}`,
      chapterRange: `${group[0]?.index || 1}—${group.at(-1)?.index || 1}章`,
      rhythm: index === 0 ? "快速建立人物与处境" : "事件推进与阶段升级",
      description: group
        .map((chapter) => `${chapter.title}：${chapter.content.slice(0, 70)}`)
        .join("；"),
      highlightDensity: "本地基础分析仅统计显性关键词，建议使用双模型生成精确密度",
      evidenceChapterIds: group.map((chapter) => chapter.id),
    };
  });
  const raw = document.rawText;
  const dialogueMarks = keywordCount(raw, /[“”]/g);
  const conflictMarks = keywordCount(
    raw,
    /反击|突破|震惊|不可能|杀|赢|败|仇|怒|危机/g,
  );
  const categories: BookAnalysisHighlightCategory[] = [
    {
      type: "冲突与反转",
      intensity: conflictMarks > 20 ? "强烈" : "中等",
      mechanism: `全文检测到约 ${conflictMarks} 处显性冲突/反转信号`,
      representativeScenes: chapters
        .slice(0, 3)
        .map((chapter) => `${chapter.title}中的主要冲突`),
      evidenceChapterIds: openingIds,
    },
  ];
  const baseTechnique = offlineTechnique(
    "章节钩子",
    "通过章节边界和事件未完成状态维持阅读期待",
    "每章只留下一个最强未完成行动或信息差，并在下一章尽快兑现",
    openingIds,
  );
  const protagonist = fallbackCharacter(characters[0], document);
  const report: BookAnalysisReport = {
    title: document.title,
    meta: {
      sourceTitle: document.title,
      author: document.author,
      charCount: document.charCount,
      chapterCount: chapters.length,
      genreTags: [
        /系统/.test(raw) ? "系统流" : "",
        /重生/.test(raw) ? "重生" : "",
        /玄|宗门|修为/.test(raw) ? "玄幻" : "类型网文",
      ].filter(Boolean),
      logline: document.intro || `${protagonist.name}围绕核心目标持续破局并改变自身处境。`,
      targetReader: "偏好强情节、连续升级与章末钩子的类型网文读者",
      summary:
        document.intro ||
        chapters
          .slice(0, 5)
          .map((chapter) => `${chapter.title}：${chapter.content.slice(0, 90)}`)
          .join("；"),
    },
    structure: {
      classification: "本地规则识别：章节推进型网文结构",
      openingHook: chapters
        .slice(0, 3)
        .map((chapter) => `${chapter.title}：${chapter.content.slice(0, 90)}`)
        .join("；"),
      rhythmOverview: "已按章节均匀划分阶段；精确的蓄力—爆发周期需要双模型证据分析。",
      phases,
      foreshadowing: [],
      strengths: ["章节边界清晰，可建立连续的事件证据链"],
      risks: ["离线模式无法可靠判断隐性伏笔和跨章回收质量"],
    },
    characters: {
      protagonist,
      antagonists: characters
        .filter((character) => /反派|敌|对手/.test(character.role))
        .slice(0, 4)
        .map((character) => fallbackCharacter(character, document)),
      supporting: characters
        .filter((character) => character.id !== characters[0]?.id)
        .slice(0, 6)
        .map((character) => fallbackCharacter(character, document)),
      relationshipOverview: "人物关系来自本地高频角色识别，需由模型结合具体事件校准。",
      evaluation: `识别到 ${characters.length} 位主要人物；建议在线生成以消除同名、别名和称谓歧义。`,
    },
    highlights: {
      overview: "本地模式依据显性冲突关键词与章节边界建立基础爽点轮廓。",
      categories,
      peakZone: "需由双模型逐块分析后确定",
      droughtZone: "需由双模型逐块分析后确定",
      averageInterval: "暂不做无证据估算",
      signatureMoments: chapters
        .slice(0, 3)
        .map((chapter) => `${chapter.title}中的核心事件`),
      strengths: ["可快速定位显性冲突和反转候选"],
      risks: ["隐性情绪释放、甜宠和关系反转可能被规则漏检"],
    },
    style: {
      language: "以中文类型叙事为主，需结合模型分析词汇和句式偏好。",
      narration: "章节化推进，叙述与事件链并行。",
      sceneWriting: "可从章节内容中进一步提取动作、环境和感官描写比例。",
      dialogue: `全文检测到约 ${dialogueMarks} 个中文引号标记，可作为对白密度的基础参考。`,
      emotionalControl: "显性冲突词可定位高压节点，但完整情绪曲线需语义分析。",
      techniques: [baseTechnique],
    },
    learning: {
      techniques: [baseTechnique],
      structureBlueprint: [
        "开篇建立人物处境与未完成目标",
        "用连续阻碍推动阶段升级",
        "在关键章节兑现一部分承诺并抛出更高层问题",
      ],
      imitationDirections: ["复用章节钩子与事件升级方法，不复制人物和设定"],
      pitfalls: ["不要把关键词统计当成最终文学判断", "隐性伏笔必须回到原文章节人工核对"],
      score: 6,
      recommendation: "当前为本地基础报告；配置双模型后重新一键拆书可获得完整证据分析。",
    },
  };
  const warnings = [
    "当前未使用双模型，仅生成可离线验收的基础拆书报告。",
    ...validateBookAnalysisReport(report, document),
  ];
  const version = createInitialVersion(report);
  return {
    report,
    versions: [version],
    currentVersion: 0,
    generatedAt: new Date().toISOString(),
    mode: "offline",
    totalChunks: chunks.length,
    analyzedChunks: chunks.length,
    coveragePercent: 100,
    warnings,
  };
}

export async function reviseBookAnalysis(params: {
  result: BookAnalysisResult;
  document: NovelDocument;
  instruction: string;
  callStructured: StructuredCaller;
}): Promise<BookAnalysisResult> {
  const { result, document, instruction, callStructured } = params;
  const revised = await callModelStage<BookAnalysisReport>(
    callStructured,
    "book_analysis_revision",
    {
      instructions: `You are a book-analysis revision editor. Apply the user's instruction only to directly relevant content; preserve every other conclusion and chapter citation.
Never remove book metadata, required analysis modules, or evidenceChapterIds. Never rewrite an uncertain claim as established fact.
Return the complete structured report. Write every natural-language field in ${result.outputLanguage || "Simplified Chinese"}.`,
      input: `[User Instruction]
${instruction}

[Current Report]
${JSON.stringify(result.report)}`,
      name: "book_analysis_revision",
      schema: reportSchema,
    },
  );
  revised.meta = {
    ...revised.meta,
    sourceTitle: document.title,
    author: document.author,
    charCount: document.charCount,
    chapterCount: document.chapters.length,
  };
  normalizeEvidenceIds(revised, document);
  const version: BookAnalysisVersion = {
    id: crypto.randomUUID(),
    instruction,
    createdAt: new Date().toISOString(),
    report: revised,
  };
  const versions = [...result.versions, version].slice(-8);
  return {
    ...result,
    report: revised,
    versions,
    currentVersion: versions.length - 1,
    warnings: validateBookAnalysisReport(revised, document),
  };
}

export function selectBookAnalysisVersion(
  result: BookAnalysisResult,
  index: number,
) {
  const safeIndex = Math.max(0, Math.min(result.versions.length - 1, index));
  return {
    ...result,
    report: result.versions[safeIndex]?.report || result.report,
    currentVersion: safeIndex,
  };
}

function list(items: string[]) {
  return items.length ? items.map((item) => `- ${item}`).join("\n") : "- 暂无可靠证据";
}

function evidence(ids: string[]) {
  return ids.length ? `（证据：${ids.join("、")}）` : "（证据待复核）";
}

function renderCharacter(character: BookAnalysisCharacter) {
  return [
    `### ${character.name}`,
    `- 身份：${character.identity}`,
    `- 叙事功能：${character.narrativeFunction}`,
    `- 核心动机：${character.motivation}`,
    `- 成长弧：${character.arc}`,
    `- 关系：${character.relationships.join("；") || "待补充"}`,
    `- ${evidence(character.evidenceChapterIds)}`,
  ].join("\n");
}

function renderTechnique(item: BookAnalysisTechnique) {
  return `- **${item.name}**：${item.observation}；复用方法：${item.reusableMethod} ${evidence(item.evidenceChapterIds)}`;
}

export function renderBookAnalysisMarkdown(result: BookAnalysisResult) {
  const report = result.report;
  return [
    `# 《${report.title}》拆书报告`,
    "",
    `> 覆盖 ${result.analyzedChunks}/${result.totalChunks} 个证据块（${result.coveragePercent}%） · ${result.mode === "online" ? "双模型深度分析" : "本地基础分析"}`,
    "",
    "## 一、书籍元信息",
    `- 原书名：${report.meta.sourceTitle}`,
    `- 作者：${report.meta.author}`,
    `- 规模：${report.meta.chapterCount}章 / ${report.meta.charCount}字`,
    `- 类型标签：${report.meta.genreTags.join("、")}`,
    `- 一句话卖点：${report.meta.logline}`,
    `- 目标读者：${report.meta.targetReader}`,
    `- 故事梗概：${report.meta.summary}`,
    "",
    "## 二、叙事结构深度分析",
    `- 结构归类：${report.structure.classification}`,
    `- 开篇钩子：${report.structure.openingHook}`,
    `- 节奏总览：${report.structure.rhythmOverview}`,
    "",
    ...report.structure.phases.flatMap((phase) => [
      `### ${phase.name}（${phase.chapterRange}）`,
      `${phase.description}`,
      `- 节奏：${phase.rhythm}`,
      `- 爽点密度：${phase.highlightDensity}`,
      `- ${evidence(phase.evidenceChapterIds)}`,
      "",
    ]),
    "### 伏笔与回收",
    ...(report.structure.foreshadowing.length
      ? report.structure.foreshadowing.map(
          (item) =>
            `- ${item.content}｜埋设：${item.planted}｜回收：${item.revealed}｜${item.quality} ${evidence(item.evidenceChapterIds)}`,
        )
      : ["- 暂无可靠证据"]),
    "",
    "### 结构优势",
    list(report.structure.strengths),
    "",
    "### 结构风险",
    list(report.structure.risks),
    "",
    "## 三、人物体系分析",
    renderCharacter(report.characters.protagonist),
    "",
    "### 反派梯队",
    ...(report.characters.antagonists.length
      ? report.characters.antagonists.map(renderCharacter)
      : ["暂无可靠证据"]),
    "",
    "### 核心配角",
    ...(report.characters.supporting.length
      ? report.characters.supporting.map(renderCharacter)
      : ["暂无可靠证据"]),
    "",
    `- 关系总览：${report.characters.relationshipOverview}`,
    `- 人物体系总评：${report.characters.evaluation}`,
    "",
    "## 四、爽点与卖点深度分析",
    report.highlights.overview,
    "",
    ...report.highlights.categories.map(
      (item) =>
        `- **${item.type} / ${item.intensity}**：${item.mechanism}；代表场景：${item.representativeScenes.join("；")} ${evidence(item.evidenceChapterIds)}`,
    ),
    "",
    `- 高峰区：${report.highlights.peakZone}`,
    `- 低谷区：${report.highlights.droughtZone}`,
    `- 平均间隔：${report.highlights.averageInterval}`,
    `- 标志性时刻：${report.highlights.signatureMoments.join("；")}`,
    "",
    "### 卖点优势",
    list(report.highlights.strengths),
    "",
    "### 卖点风险",
    list(report.highlights.risks),
    "",
    "## 五、文笔与写作技法分析",
    `- 语言：${report.style.language}`,
    `- 叙事：${report.style.narration}`,
    `- 场景：${report.style.sceneWriting}`,
    `- 对话：${report.style.dialogue}`,
    `- 情绪控制：${report.style.emotionalControl}`,
    "",
    ...report.style.techniques.map(renderTechnique),
    "",
    "## 六、学习与仿写实操指南",
    ...report.learning.techniques.map(renderTechnique),
    "",
    "### 结构复用方案",
    list(report.learning.structureBlueprint),
    "",
    "### 仿写方向",
    list(report.learning.imitationDirections),
    "",
    "### 需要规避",
    list(report.learning.pitfalls),
    "",
    `- 综合评分：${report.learning.score}/10`,
    `- 推荐理由：${report.learning.recommendation}`,
    "",
    ...(result.warnings.length
      ? ["## 质检提示", list(result.warnings), ""]
      : []),
  ].join("\n");
}

function looksLikeReport(value: unknown): value is BookAnalysisReport {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const report = value as Record<string, unknown>;
  return Boolean(
    typeof report.title === "string" &&
      report.meta &&
      report.structure &&
      report.characters &&
      report.highlights &&
      report.style &&
      report.learning,
  );
}

export function sanitizeBookAnalysisResult(
  value: unknown,
): BookAnalysisResult | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const source = value as Record<string, unknown>;
  if (!looksLikeReport(source.report)) return null;
  const versions = Array.isArray(source.versions)
    ? source.versions.flatMap<BookAnalysisVersion>((item, index) => {
        if (!item || typeof item !== "object" || Array.isArray(item)) return [];
        const version = item as Record<string, unknown>;
        if (!looksLikeReport(version.report)) return [];
        return [
          {
            id:
              typeof version.id === "string"
                ? version.id
                : `book-version-${index + 1}`,
            instruction:
              typeof version.instruction === "string"
                ? version.instruction
                : "历史版本",
            createdAt:
              typeof version.createdAt === "string"
                ? version.createdAt
                : new Date().toISOString(),
            report: version.report,
          },
        ];
      })
    : [];
  const safeVersions = versions.length
    ? versions
    : [createInitialVersion(source.report)];
  const currentVersion =
    typeof source.currentVersion === "number"
      ? Math.max(
          0,
          Math.min(safeVersions.length - 1, Math.floor(source.currentVersion)),
        )
      : safeVersions.length - 1;
  return {
    report: safeVersions[currentVersion]?.report || source.report,
    versions: safeVersions,
    currentVersion,
    generatedAt:
      typeof source.generatedAt === "string"
        ? source.generatedAt
        : new Date().toISOString(),
    mode: source.mode === "online" ? "online" : "offline",
    totalChunks:
      typeof source.totalChunks === "number" ? source.totalChunks : 0,
    analyzedChunks:
      typeof source.analyzedChunks === "number" ? source.analyzedChunks : 0,
    coveragePercent:
      typeof source.coveragePercent === "number"
        ? source.coveragePercent
        : 0,
    warnings: Array.isArray(source.warnings)
      ? source.warnings.filter(
          (item): item is string => typeof item === "string",
        )
      : [],
  };
}

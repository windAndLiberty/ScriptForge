export type ModelRoute = "primary" | "flash";

export type ModelStage =
  | "character_naming"
  | "chapter_analysis"
  | "story_bible"
  | "story_bible_repair"
  | "episode_outline"
  | "episode_outline_repair"
  | "episode_draft"
  | "episode_semantic_audit"
  | "episode_repair"
  | "series_quality_audit"
  | "series_quality_repair"
  | "book_analysis_extract"
  | "book_analysis_digest"
  | "book_analysis_structure"
  | "book_analysis_characters"
  | "book_analysis_commercial"
  | "book_analysis_revision";

export type StructuredCaller = <T>(payload: {
  instructions: string;
  input: string;
  name: string;
  schema: Record<string, unknown>;
  route?: ModelRoute;
}) => Promise<T>;

const MODEL_POLICY: Record<ModelStage, ModelRoute> = {
  character_naming: "flash",
  chapter_analysis: "flash",
  story_bible: "primary",
  story_bible_repair: "primary",
  episode_outline: "primary",
  episode_outline_repair: "primary",
  episode_draft: "primary",
  episode_semantic_audit: "flash",
  episode_repair: "primary",
  series_quality_audit: "flash",
  series_quality_repair: "primary",
  book_analysis_extract: "flash",
  book_analysis_digest: "flash",
  book_analysis_structure: "primary",
  book_analysis_characters: "primary",
  book_analysis_commercial: "primary",
  book_analysis_revision: "primary",
};

export function routeForStage(stage: ModelStage): ModelRoute {
  return MODEL_POLICY[stage];
}

export function callModelStage<T>(
  caller: StructuredCaller,
  stage: ModelStage,
  payload: Omit<Parameters<StructuredCaller>[0], "route">,
) {
  return caller<T>({
    ...payload,
    route: routeForStage(stage),
  });
}

export function modelPolicySnapshot() {
  return { ...MODEL_POLICY };
}

/// <reference types="vite/client" />

interface ModelSettings {
  provider: string;
  protocol: "responses" | "chat";
  authMode: "bearer" | "api-key" | "x-api-key" | "x-goog-api-key" | "none";
  structuredOutput: "json_schema" | "json_object" | "prompt_only";
  baseUrl: string;
  model: string;
  flashModel: string;
  imageModel: string;
  speechModel: string;
  speechVoice: string;
  consentedEndpointHost: string;
  sendReasoning: boolean;
  reasoningEffort: "none" | "low" | "medium" | "high";
  hasApiKey: boolean;
  hasFlashModel: boolean;
  apiKeyHint: string;
}

interface DesktopAPI {
  isDesktop: boolean;
  openTextFile: () => Promise<{ path: string; name: string; text: string } | null>;
  openDocument: () => Promise<{ path: string; name: string; format: string; text: string } | null>;
  readDroppedDocument: (file: File) => Promise<{ path: string; name: string; format: string; text: string }>;
  saveTextFile: (payload: {
    fileName: string;
    content: string;
    extension?: "txt" | "md";
  }) => Promise<string | null>;
  saveExport: (payload: {
    fileName: string;
    extension: "txt" | "md" | "json" | "docx";
    content?: string;
    document?: unknown;
  }) => Promise<string | null>;
  saveProject: (project: unknown) => Promise<{ project: unknown; path: string }>;
  loadProject: <T>(projectId: string) => Promise<T>;
  listProjects: <T>() => Promise<T[]>;
  duplicateProject: (payload: { sourceProjectId: string; project: unknown }) => Promise<{ project: unknown; path: string }>;
  deleteProject: (projectId: string) => Promise<boolean>;
  writeProjectJson: (payload: { projectId: string; category: string; itemId: string; value: unknown }) => Promise<string>;
  readProjectJson: <T>(payload: { projectId: string; relativePath: string }) => Promise<T>;
  writeProjectText: (payload: { projectId: string; category: string; itemId: string; content: string }) => Promise<string>;
  readProjectText: (payload: { projectId: string; relativePath: string }) => Promise<string>;
  getSettings: () => Promise<ModelSettings>;
  updateSettings: (
    payload: Partial<ModelSettings> & { apiKey?: string; clearApiKey?: boolean; confirmEndpoint?: boolean },
  ) => Promise<ModelSettings>;
  callStructured: <T>(payload: {
    instructions: string;
    input: string;
    name: string;
    schema: Record<string, unknown>;
    route?: "primary" | "flash";
  }) => Promise<T>;
  generateImage: (payload: { projectId: string; episodeId: string; shotId: string; prompt: string }) => Promise<string>;
  synthesizeSpeech: (payload: { projectId: string; episodeId: string; shotId: string; text: string }) => Promise<string>;
  readProjectMedia: (payload: { projectId: string; relativePath: string }) => Promise<string>;
  getVersion: () => Promise<string>;
}

interface Window {
  desktopAPI?: DesktopAPI;
}

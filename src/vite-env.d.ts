/// <reference types="vite/client" />

interface ModelSettings {
  provider: string;
  protocol: "responses" | "chat";
  baseUrl: string;
  model: string;
  flashModel: string;
  reasoningEffort: "none" | "low" | "medium" | "high";
  hasApiKey: boolean;
  hasFlashModel: boolean;
  apiKeyHint: string;
}

interface DesktopAPI {
  isDesktop: boolean;
  openTextFile: () => Promise<{ path: string; name: string; text: string } | null>;
  saveTextFile: (payload: {
    fileName: string;
    content: string;
    extension?: "txt" | "md";
  }) => Promise<string | null>;
  getSettings: () => Promise<ModelSettings>;
  updateSettings: (
    payload: Partial<ModelSettings> & { apiKey?: string; clearApiKey?: boolean },
  ) => Promise<ModelSettings>;
  callStructured: <T>(payload: {
    instructions: string;
    input: string;
    name: string;
    schema: Record<string, unknown>;
    route?: "primary" | "flash";
  }) => Promise<T>;
  getVersion: () => Promise<string>;
}

interface Window {
  desktopAPI?: DesktopAPI;
}

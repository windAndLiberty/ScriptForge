const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("desktopAPI", {
  isDesktop: true,
  openTextFile: () => ipcRenderer.invoke("file:open-text"),
  saveTextFile: (payload) => ipcRenderer.invoke("file:save-text", payload),
  getSettings: () => ipcRenderer.invoke("settings:get"),
  updateSettings: (payload) => ipcRenderer.invoke("settings:update", payload),
  callStructured: (payload) => ipcRenderer.invoke("llm:structured", payload),
  getVersion: () => ipcRenderer.invoke("app:version"),
});

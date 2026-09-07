const fs = require("node:fs/promises");
const path = require("node:path");

function cleanSegment(value) {
  const cleaned = String(value || "").replace(/[^a-zA-Z0-9._-]/g, "_");
  if (!cleaned || cleaned === "." || cleaned === "..") throw new Error("Invalid project path segment.");
  return cleaned;
}

function cleanCategory(value) {
  return String(value || "").split(/[\\/]+/).filter(Boolean).map(cleanSegment).join(path.sep);
}

class ProjectStore {
  constructor(root) {
    this.root = root;
  }

  projectRoot(projectId) {
    return path.join(this.root, "projects", cleanSegment(projectId));
  }

  async atomicWrite(filePath, data) {
    await fs.mkdir(path.dirname(filePath), { recursive: true });
    const temporary = `${filePath}.${process.pid}.${Date.now()}.tmp`;
    await fs.writeFile(temporary, data);
    await fs.rename(temporary, filePath);
  }

  async saveProject(project) {
    if (!project?.id) throw new Error("Project ID is required.");
    const root = this.projectRoot(project.id);
    const stored = { ...project, schemaVersion: 5, updatedAt: new Date().toISOString() };
    if (stored.creativeWorkspace) {
      const workspacePath = "creative/workspace.json";
      await this.atomicWrite(path.join(root, workspacePath), JSON.stringify(stored.creativeWorkspace, null, 2));
      stored.creativeWorkspaceIndex = workspacePath;
      delete stored.creativeWorkspace;
    }
    await this.atomicWrite(path.join(root, "project.json"), JSON.stringify(stored, null, 2));
    return { project: { ...stored, creativeWorkspace: project.creativeWorkspace }, path: root };
  }

  async loadProject(projectId) {
    const raw = await fs.readFile(path.join(this.projectRoot(projectId), "project.json"), "utf8");
    const project = JSON.parse(raw);
    if (project.creativeWorkspaceIndex) {
      try {
        project.creativeWorkspace = JSON.parse(await fs.readFile(path.join(this.projectRoot(projectId), project.creativeWorkspaceIndex), "utf8"));
      } catch {
        project.creativeWorkspace = undefined;
      }
    }
    return project;
  }

  async listProjects() {
    const projectsRoot = path.join(this.root, "projects");
    let entries = [];
    try { entries = await fs.readdir(projectsRoot, { withFileTypes: true }); } catch { return []; }
    const values = await Promise.all(entries.filter((entry) => entry.isDirectory()).map(async (entry) => {
      try { return await this.loadProject(entry.name); } catch { return null; }
    }));
    return values.filter(Boolean).sort((a, b) => String(b.updatedAt).localeCompare(String(a.updatedAt)));
  }

  async duplicateProject(sourceProjectId, project) {
    const source = this.projectRoot(sourceProjectId);
    const target = this.projectRoot(project.id);
    await fs.mkdir(path.dirname(target), { recursive: true });
    await fs.cp(source, target, { recursive: true, force: false, errorOnExist: true });
    return this.saveProject(project);
  }

  async deleteProject(projectId) {
    await fs.rm(this.projectRoot(projectId), { recursive: true, force: true });
    return true;
  }

  async writeJson(projectId, category, itemId, value) {
    const relative = path.join(cleanCategory(category), `${cleanSegment(itemId)}.json`);
    await this.atomicWrite(path.join(this.projectRoot(projectId), relative), JSON.stringify(value, null, 2));
    return relative.replaceAll(path.sep, "/");
  }

  async readJson(projectId, relativePath) {
    const root = this.projectRoot(projectId);
    const target = path.resolve(root, relativePath);
    if (!target.startsWith(`${path.resolve(root)}${path.sep}`)) throw new Error("Invalid project file path.");
    return JSON.parse(await fs.readFile(target, "utf8"));
  }

  async writeText(projectId, category, itemId, content) {
    const relative = path.join(cleanCategory(category), `${cleanSegment(itemId)}.md`);
    await this.atomicWrite(path.join(this.projectRoot(projectId), relative), String(content));
    return relative.replaceAll(path.sep, "/");
  }

  async readText(projectId, relativePath) {
    const root = this.projectRoot(projectId);
    const target = path.resolve(root, relativePath);
    if (!target.startsWith(`${path.resolve(root)}${path.sep}`)) throw new Error("Invalid project file path.");
    return fs.readFile(target, "utf8");
  }

  async writeBinary(projectId, category, itemId, extension, content) {
    const relative = path.join(cleanCategory(category), `${cleanSegment(itemId)}.${cleanSegment(extension)}`);
    await this.atomicWrite(path.join(this.projectRoot(projectId), relative), content);
    return relative.replaceAll(path.sep, "/");
  }

  async readBinary(projectId, relativePath) {
    const root = this.projectRoot(projectId);
    const target = path.resolve(root, relativePath);
    if (!target.startsWith(`${path.resolve(root)}${path.sep}`)) throw new Error("Invalid project media path.");
    return fs.readFile(target);
  }
}

module.exports = { ProjectStore };

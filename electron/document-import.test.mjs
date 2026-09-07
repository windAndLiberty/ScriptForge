import { afterEach, describe, expect, it } from "vitest";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const JSZip = require("jszip");
const { readDocument, SUPPORTED_EXTENSIONS } = require("./document-import.cjs");
const { ProjectStore } = require("./project-store.cjs");
const { makeDocx } = require("./docx-export.cjs");

const roots = [];
afterEach(async () => {
  await Promise.all(roots.splice(0).map((root) => fs.rm(root, { recursive: true, force: true })));
});

async function temporaryRoot() {
  const value = await fs.mkdtemp(path.join(os.tmpdir(), "scriptforge-test-"));
  roots.push(value);
  return value;
}

describe("Windows document import", () => {
  it("advertises every common manuscript format", () => {
    expect(SUPPORTED_EXTENSIONS).toEqual(expect.arrayContaining(["txt", "md", "rtf", "docx", "doc", "pdf", "html", "odt"]));
  });

  it("extracts text from RTF, HTML, and DOCX", async () => {
    const root = await temporaryRoot();
    const rtf = path.join(root, "sample.rtf");
    const html = path.join(root, "sample.html");
    const docx = path.join(root, "sample.docx");
    await fs.writeFile(rtf, "{\\rtf1\\ansi First paragraph\\par Second paragraph}");
    await fs.writeFile(html, "<h1>Story</h1><p>Opening line.</p>");
    const zip = new JSZip();
    zip.file("word/document.xml", '<?xml version="1.0"?><w:document xmlns:w="x"><w:body><w:p><w:r><w:t>Chapter One</w:t></w:r></w:p><w:p><w:r><w:t>Opening line.</w:t></w:r></w:p></w:body></w:document>');
    await fs.writeFile(docx, await zip.generateAsync({ type: "nodebuffer" }));
    expect((await readDocument(rtf)).text).toContain("Second paragraph");
    expect((await readDocument(html)).text).toContain("Opening line.");
    expect((await readDocument(docx)).text).toContain("Chapter One\nOpening line.");
  });

  it("re-imports an exported DOCX without losing volume, chapter, or body order", async () => {
    const root = await temporaryRoot();
    const target = path.join(root, "roundtrip.docx");
    await fs.writeFile(target, await makeDocx({ projectName: "Novel", chapters: [
      { number: 1, volumeNumber: 1, volumeTitle: "Volume One", title: "Arrival", heading: "Chapter 1: Arrival", content: "First body paragraph.\nSecond body paragraph." },
      { number: 2, volumeNumber: 1, volumeTitle: "Volume One", title: "Choice", heading: "Chapter 2: Choice", content: "Third body paragraph." },
    ] }));
    const text = (await readDocument(target)).text;
    expect(text.indexOf("Volume One")).toBeLessThan(text.indexOf("Chapter 1: Arrival"));
    expect(text.indexOf("First body paragraph.")).toBeLessThan(text.indexOf("Chapter 2: Choice"));
    expect(text).toContain("Third body paragraph.");
  });
});

describe("schema v5 project store", () => {
  it("opens a v4 project without rewriting it, then upgrades on save", async () => {
    const root = await temporaryRoot();
    const projectRoot = path.join(root, "projects", "legacy");
    await fs.mkdir(projectRoot, { recursive: true });
    const projectPath = path.join(projectRoot, "project.json");
    const original = JSON.stringify({ id: "legacy", name: "Legacy", schemaVersion: 4 });
    await fs.writeFile(projectPath, original);
    const store = new ProjectStore(root);
    expect((await store.loadProject("legacy")).schemaVersion).toBe(4);
    expect(await fs.readFile(projectPath, "utf8")).toBe(original);
    await store.saveProject(await store.loadProject("legacy"));
    expect(JSON.parse(await fs.readFile(projectPath, "utf8")).schemaVersion).toBe(5);
  });

  it("atomically keeps project index, runs, artifacts, and chapter versions together", async () => {
    const root = await temporaryRoot();
    const store = new ProjectStore(root);
    const saved = await store.saveProject({ id: "project-1", name: "Novel", schemaVersion: 4 });
    expect(saved.project.schemaVersion).toBe(5);
    const runPath = await store.writeJson("project-1", "runs", "run-1", { status: "interrupted" });
    const versionPath = await store.writeText("project-1", "chapters/chapter-1/versions", "version-1", "Draft text");
    expect(await store.readJson("project-1", runPath)).toEqual({ status: "interrupted" });
    expect(await store.readText("project-1", versionPath)).toBe("Draft text");
    expect((await store.listProjects())[0].name).toBe("Novel");
  });

  it("duplicates and deletes the complete self-contained project folder", async () => {
    const root = await temporaryRoot();
    const store = new ProjectStore(root);
    await store.saveProject({ id: "source", name: "Source", creativeWorkspace: { chapters: [] } });
    const versionPath = await store.writeText("source", "chapters/chapter/versions", "v1", "Accepted chapter");
    await store.duplicateProject("source", { id: "copy", name: "Copy", creativeWorkspace: { chapters: [] } });
    expect(await store.readText("copy", versionPath)).toBe("Accepted chapter");
    await store.deleteProject("source");
    expect((await store.listProjects()).map((item) => item.id)).toEqual(["copy"]);
  });
});

const JSZip = require("jszip");

function escapeXml(value) {
  return String(value).replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;").replaceAll("'", "&apos;");
}

async function makeDocx(payload) {
  const zip = new JSZip();
  zip.file("[Content_Types].xml", `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>`);
  zip.file("_rels/.rels", `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>`);
  const paragraphs = [];
  const add = (text, style) => { const property = style ? `<w:pPr><w:pStyle w:val="${style}"/></w:pPr>` : ""; paragraphs.push(text ? `<w:p>${property}<w:r><w:t xml:space="preserve">${escapeXml(text)}</w:t></w:r></w:p>` : "<w:p/>"); };
  add(payload.projectName || "ScriptForge Export", "Title");
  let volumeNumber = null;
  for (const chapter of payload.chapters || []) {
    if (chapter.volumeNumber !== volumeNumber) { add(chapter.volumeTitle || `Volume ${chapter.volumeNumber}`, "Heading1"); volumeNumber = chapter.volumeNumber; }
    add(chapter.heading || `Chapter ${chapter.number}: ${chapter.title}`, "Heading2");
    String(chapter.content || "").split(/\r?\n/).forEach((line) => add(line, null));
  }
  zip.file("word/document.xml", `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>${paragraphs.join("")}<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr></w:body></w:document>`);
  return zip.generateAsync({ type: "nodebuffer", compression: "DEFLATE" });
}

module.exports = { makeDocx };

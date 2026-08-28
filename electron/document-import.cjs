const fs = require("node:fs/promises");
const path = require("node:path");
const JSZip = require("jszip");
const iconv = require("iconv-lite");
const WordExtractor = require("word-extractor");

const SUPPORTED_EXTENSIONS = ["txt", "text", "md", "markdown", "rtf", "docx", "doc", "pdf", "html", "htm", "odt"];

function decodeEntities(text) {
  return text
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;|&apos;/gi, "'")
    .replace(/&#(\d+);/g, (_, value) => String.fromCodePoint(Number(value)));
}

function xmlToText(xml) {
  return decodeEntities(
    xml
      .replace(/<w:tab\s*\/>/gi, "\t")
      .replace(/<w:br\s*\/?\s*>/gi, "\n")
      .replace(/<\/w:p\s*>/gi, "\n")
      .replace(/<text:tab\s*\/>/gi, "\t")
      .replace(/<text:line-break\s*\/>/gi, "\n")
      .replace(/<\/text:p\s*>/gi, "\n")
      .replace(/<[^>]+>/g, ""),
  )
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function htmlToText(html) {
  return decodeEntities(
    html
      .replace(/<script[\s\S]*?<\/script>/gi, "")
      .replace(/<style[\s\S]*?<\/style>/gi, "")
      .replace(/<\/?(?:p|div|h[1-6]|li|blockquote|tr)[^>]*>/gi, "\n")
      .replace(/<br\s*\/?\s*>/gi, "\n")
      .replace(/<[^>]+>/g, ""),
  )
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function rtfToText(rtf) {
  return rtf
    .replace(/\\u(-?\d+)\??/g, (_, value) => {
      const point = Number(value);
      return String.fromCharCode(point < 0 ? point + 65536 : point);
    })
    .replace(/\\'([0-9a-f]{2})/gi, (_, hex) => iconv.decode(Buffer.from(hex, "hex"), "windows-1252"))
    .replace(/\\(?:par|line)\b/g, "\n")
    .replace(/\\tab\b/g, "\t")
    .replace(/\\[a-z]+-?\d* ?/gi, "")
    .replace(/[{}]/g, "")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function decodeText(buffer) {
  if (buffer[0] === 0xff && buffer[1] === 0xfe) return iconv.decode(buffer.subarray(2), "utf16-le");
  if (buffer[0] === 0xfe && buffer[1] === 0xff) return iconv.decode(buffer.subarray(2), "utf16-be");
  const utf8 = iconv.decode(buffer, "utf8");
  const replacementRate = (utf8.match(/�/g) || []).length / Math.max(1, utf8.length);
  return replacementRate > 0.002 ? iconv.decode(buffer, "gb18030") : utf8.replace(/^\uFEFF/, "");
}

async function extractPdf(buffer) {
  const pdfjs = await import("pdfjs-dist/legacy/build/pdf.mjs");
  const document = await pdfjs.getDocument({ data: new Uint8Array(buffer), disableWorker: true }).promise;
  const pages = [];
  for (let number = 1; number <= document.numPages; number += 1) {
    const page = await document.getPage(number);
    const content = await page.getTextContent();
    pages.push(content.items.map((item) => ("str" in item ? item.str : "")).join(" "));
  }
  return pages.join("\n\n").trim();
}

async function extractZipXml(buffer, fileName) {
  const zip = await JSZip.loadAsync(buffer);
  const entry = zip.file(fileName);
  if (!entry) throw new Error(`The document is missing ${fileName}.`);
  return xmlToText(await entry.async("string"));
}

async function readDocument(filePath) {
  const extension = path.extname(filePath).slice(1).toLowerCase();
  if (!SUPPORTED_EXTENSIONS.includes(extension)) {
    throw new Error(`Unsupported document format: .${extension || "unknown"}`);
  }
  const buffer = await fs.readFile(filePath);
  let text = "";
  if (["txt", "text", "md", "markdown"].includes(extension)) text = decodeText(buffer);
  else if (extension === "rtf") text = rtfToText(decodeText(buffer));
  else if (extension === "html" || extension === "htm") text = htmlToText(decodeText(buffer));
  else if (extension === "docx") text = await extractZipXml(buffer, "word/document.xml");
  else if (extension === "odt") text = await extractZipXml(buffer, "content.xml");
  else if (extension === "pdf") text = await extractPdf(buffer);
  else if (extension === "doc") {
    const extractor = new WordExtractor();
    const document = await extractor.extract(filePath);
    text = document.getBody().trim();
  }
  if (!text.trim()) throw new Error("The document contains no readable text.");
  return { path: filePath, name: path.basename(filePath), format: extension, text: text.trim() };
}

module.exports = { SUPPORTED_EXTENSIONS, readDocument };


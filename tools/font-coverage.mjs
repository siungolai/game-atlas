// 读取 woff2 的 cmap 表，枚举字体真实覆盖的码位。
// 用法: node tools/font-coverage.mjs <font.woff2> [更多字体...] [--json]
import fs from "node:fs";
import { brotliDecompressSync } from "node:zlib";

const TAG_ORDER = [
  "cmap","head","hhea","hmtx","maxp","name","OS/2","post","cvt ","fpgm","glyf","loca",
  "prep","CFF ","VORG","EBDT","EBLC","gasp","hdmx","kern","LTSH","PCLT","VDMX","vhea",
  "vmtx","BASE","GDEF","GPOS","GSUB","EBSC","JSTF","MATH","CBDT","CBLC","COLR","CPAL",
  "SVG ","sbix","acnt","avar","bdat","bloc","bsln","cvar","fdsc","feat","fmtx","fvar",
  "gvar","hsty","just","lcar","mort","morx","opbd","prop","trak","Zapf","Silf","Glat",
  "Gloc","Feat","Sill",
];

function u128(buf, pos) {
  let v = 0;
  for (let i = 0; i < 5; i++) {
    const b = buf[pos++];
    v = v * 128 + (b & 0x7f);
    if (!(b & 0x80)) return [v, pos];
  }
  throw new Error("UIntBase128 溢出");
}

function parseCmapTable(cmap) {
  const numTables = cmap.readUInt16BE(2);
  const subtables = [];
  for (let i = 0; i < numTables; i++) {
    const p = 4 + i * 8;
    const platformID = cmap.readUInt16BE(p);
    const encodingID = cmap.readUInt16BE(p + 2);
    const off = cmap.readUInt32BE(p + 4);
    subtables.push({ platformID, encodingID, off, format: cmap.readUInt16BE(off) });
  }
  const preferred =
    subtables.find((s) => s.format === 12 && s.platformID === 3) ||
    subtables.find((s) => s.format === 12) ||
    subtables.find((s) => s.format === 4 && s.platformID === 3 && s.encodingID === 1) ||
    subtables.find((s) => s.format === 4);
  if (!preferred) throw new Error("无 format 4/12 子表");
  const { off, format } = preferred;
  const codes = new Set();
  if (format === 12) {
    const nGroups = cmap.readUInt32BE(off + 12);
    for (let i = 0; i < nGroups; i++) {
      const g = off + 16 + i * 12;
      const start = cmap.readUInt32BE(g);
      const end = cmap.readUInt32BE(g + 4);
      for (let c = start; c <= end; c++) codes.add(c);
    }
    return { format, codes };
  }
  const segCount = cmap.readUInt16BE(off + 6) / 2;
  const endPos = off + 14;
  const startPos = endPos + segCount * 2 + 2;
  for (let i = 0; i < segCount; i++) {
    const end = cmap.readUInt16BE(endPos + i * 2);
    const start = cmap.readUInt16BE(startPos + i * 2);
    if (start === 0xffff) continue;
    for (let c = start; c <= end; c++) codes.add(c);
  }
  return { format, codes };
}

function readCmap(buf) {
  if (buf.toString("ascii", 0, 4) !== "wOF2") throw new Error("不是 woff2 文件");
  const numTables = buf.readUInt16BE(12);
  const compressedSize = buf.readUInt32BE(20);
  let pos = 48;
  const tables = [];
  for (let i = 0; i < numTables; i++) {
    const flags = buf[pos++];
    const tagIndex = flags & 0x3f;
    const tag = tagIndex === 63 ? buf.toString("ascii", pos, (pos += 4)) : TAG_ORDER[tagIndex];
    const tv = (flags >> 6) & 0x03;
    let origLen;
    [origLen, pos] = u128(buf, pos);
    let transformLen = null;
    const needsTransform =
      tag === "glyf" || tag === "loca" ? tv === 0 : tag === "hmtx" ? tv === 1 : false;
    if (needsTransform) [transformLen, pos] = u128(buf, pos);
    tables.push({ tag, origLen, transformLen });
  }
  const raw = brotliDecompressSync(buf.subarray(pos, pos + compressedSize));
  let offset = 0;
  for (const t of tables) {
    const size = t.transformLen ?? t.origLen;
    if (t.tag === "cmap") return parseCmapTable(raw.subarray(offset, offset + size));
    offset += size;
  }
  throw new Error("未找到 cmap 表");
}

const args = process.argv.slice(2);
const asJson = args.includes("--json");
const files = args.filter((a) => !a.startsWith("--"));
if (files.length === 0) {
  console.error("用法: node tools/font-coverage.mjs <font.woff2> [更多字体...] [--json]");
  process.exit(2);
}

const union = new Set();
const formats = new Set();
const perFile = [];
for (const file of files) {
  try {
    const { format, codes } = readCmap(fs.readFileSync(file));
    formats.add(format);
    for (const c of codes) union.add(c);
    perFile.push({ file, format, count: codes.size });
  } catch (err) {
    console.error(`读取失败: ${file} — ${err.message}`);
    process.exit(3);
  }
}

if (asJson) {
  process.stdout.write(
    JSON.stringify({ files: perFile, formats: [...formats], count: union.size, codes: [...union].sort((a, b) => a - b) })
  );
} else {
  for (const f of perFile) console.log(`${f.file}  format=${f.format}  码位=${f.count}`);
  console.log(`并集码位数=${union.size}`);
}

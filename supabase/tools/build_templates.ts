/// CAPTCHA şablonu üretici + OCR değerlendiricisi.
///
/// Kullanım:
///   deno run --config supabase/deno.json supabase/tools/build_templates.ts <örnek_dizini>
///
/// Girdi: örnek dizininde captcha_*.jpg + labels.json ({"captcha_0.jpg": "54+3=?"}).
/// Çıktı: functions/_shared/templates.ts (üretilmiş) + değerlendirme tablosu.
///
/// Etiket, görseldeki görünür metindir; segment sayısı etiket uzunluğuna
/// eşitse örnek şablona katılır (eşit değilse örneklem hatalıdır, atlanır).
import { encodeBase64 } from 'jsr:@std/encoding@1/base64';

import { GRID, type TemplateEntry } from '../functions/_shared/templates.ts';
import {
  binarize,
  glyphBitmaps,
  removeSpecks,
  toGray,
} from '../functions/_shared/ocr.ts';

const MAX_VARIANTS_PER_CHAR = 8;

const samplesDir = Deno.args[0];
if (samplesDir == null) {
  console.error('kullanım: deno run ... build_templates.ts <örnek_dizini>');
  Deno.exit(2);
}

const labels = JSON.parse(
  await Deno.readTextFile(`${samplesDir}/labels.json`),
) as Record<string, string>;

/// Adlandırma: char -> normalize edilmiş bit dizileri (tekrarlar elenir).
const collected = new Map<string, Uint8Array[]>();
let aligned = 0;
let mismatched = 0;

const rows: { file: string; label: string; segments: number; status: string }[] = [];

for (const [file, label] of Object.entries(labels)) {
  const path = `${samplesDir}/${file}`;
  let image: Uint8Array;
  try {
    image = await Deno.readFile(path);
  } catch {
    rows.push({ file, label, segments: -1, status: 'dosya yok' });
    continue;
  }

  const bits = binarize(toGray(image));
  removeSpecks(bits);
  const glyphs = glyphBitmaps(bits);

  if (glyphs.length !== label.length) {
    mismatched++;
    rows.push({ file, label, segments: glyphs.length, status: 'SEGMENT UYUMSUZ' });
    continue;
  }
  aligned++;

  for (let i = 0; i < glyphs.length; i++) {
    const char = label[i];
    const variants = collected.get(char) ?? [];
    if (variants.length >= MAX_VARIANTS_PER_CHAR) continue;
    const normalized = glyphs[i].bitmap;
    if (!variants.some((v) => v.every((value, index) => value === normalized[index]))) {
      variants.push(normalized);
    }
    collected.set(char, variants);
  }
  rows.push({ file, label, segments: glyphs.length, status: 'şablona girdi' });
}

for (const row of rows.sort((a, b) => a.file.localeCompare(b.file, undefined, { numeric: true }))) {
  console.log(
    `${row.file.padEnd(16)} etiket=${row.label.padEnd(8)} segment=${row.segments} ${row.status}`,
  );
}
console.log(`hizalı: ${aligned}, uyumsuz: ${mismatched}`);

const entries: TemplateEntry[] = [];
for (const [char, variants] of [...collected.entries()].sort((a, b) => a[0].localeCompare(b[0]))) {
  for (const bits of variants) {
    entries.push({ char, bits: encodeBase64(bits) });
  }
}

const output = `/// Bu dosya supabase/tools/build_templates.ts ile üretilmiştir.
/// Elle düzenlenmemelidir.

export interface TemplateEntry {
  /// Okunması hedeflenen karakter ("0"-"9", "+", "=", "?").
  char: string;
  /// GRID x GRID (= 24x24) piksel, bayt başına 0/1; base64 kodlu.
  bits: string;
}

export const GRID = ${GRID};

export const TEMPLATES: TemplateEntry[] = ${JSON.stringify(entries, null, 2)};

let decoded: { char: string; bits: Uint8Array }[] | null = null;

/// base64 şablonları bayt dizilerine çözer (tek seferlik).
export function decodedTemplates(): { char: string; bits: Uint8Array }[] {
  if (decoded == null) {
    decoded = TEMPLATES.map((t) => ({
      char: t.char,
      bits: Uint8Array.from(atob(t.bits), (c) => c.charCodeAt(0)),
    }));
  }
  return decoded;
}
`;

const target = new URL('../functions/_shared/templates.ts', import.meta.url);
await Deno.writeTextFile(target, output);
console.log(`yazıldı: ${target.pathname} (${entries.length} şablon)`);

const coverage = [...collected.entries()]
  .map(([char, variants]) => `${char}:${variants.length}`)
  .join(' ');
console.log(`kapsama: ${coverage}`);

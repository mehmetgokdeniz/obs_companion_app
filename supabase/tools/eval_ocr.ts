/// OCR LOO (leave-one-out) değerlendirmesi + eşik/marj kalibrasyonu.
///
/// Her örnek için diğer19'undan şablon üretilir; aday boru hattı varyantları
/// × skor/marj eşikleri taranır. Garamer (CAPTCHA_GRAMMAR) uygulanır.
/// Rapor: doğru / null (ret → manel akış) / yanlış (EN KÖTÜSÜ, sıfır olmalı).
///
/// deno run --config supabase/deno.json --allow-read \
///   supabase/tools/eval_ocr.ts <örnek_dizini>
import { solveExpression } from '../functions/_shared/expression.ts';
import {
  CAPTCHA_GRAMMAR,
  binarize,
  glyphBitmaps,
  readCaptchaTextWith,
  removeSpecks,
  toGray,
  type GrayImage,
  type SegmentOptions,
} from '../functions/_shared/ocr.ts';

const samplesDir = Deno.args[0];
if (samplesDir == null) {
  console.error('kullanım: deno run ... eval_ocr.ts <örnek_dizini>');
  Deno.exit(2);
}

const labels = JSON.parse(
  await Deno.readTextFile(`${samplesDir}/labels.json`),
) as Record<string, string>;

const names = Object.keys(labels);
const images = new Map<string, Uint8Array>();
const grays = new Map<string, GrayImage>();
for (const name of names) {
  const image = await Deno.readFile(`${samplesDir}/${name}`);
  images.set(name, image);
  grays.set(name, toGray(image));
}

interface Variant {
  label: string;
  lumaCap: number;
  chromaCap: number;
  segment: SegmentOptions;
}

const variants: Variant[] = [
  {
    label: 'A luma110 chroma130 area30 xOv2',
    lumaCap: 110,
    chromaCap: 130,
    segment: { minComponentArea: 30, mergeXOverlap: 2, mergeYGap: 8, smallMergeGap: 2 },
  },
  {
    label: 'B luma130 chroma130 area30 xOv4',
    lumaCap: 130,
    chromaCap: 130,
    segment: { minComponentArea: 30, mergeXOverlap: 4, mergeYGap: 8, smallMergeGap: 2 },
  },
  {
    label: 'C luma130 chroma90 area40 xOv2',
    lumaCap: 130,
    chromaCap: 90,
    segment: { minComponentArea: 40, mergeXOverlap: 2, mergeYGap: 8, smallMergeGap: 2 },
  },
  {
    label: 'F luma80 chroma130 area30 xOv2',
    lumaCap: 80,
    chromaCap: 130,
    segment: { minComponentArea: 30, mergeXOverlap: 2, mergeYGap: 8, smallMergeGap: 2 },
  },
  {
    label: 'G luma60 chroma130 area30 xOv2',
    lumaCap: 60,
    chromaCap: 130,
    segment: { minComponentArea: 30, mergeXOverlap: 2, mergeYGap: 8, smallMergeGap: 2 },
  },
  {
    label: 'H luma110 chroma130 area30 xOv4',
    lumaCap: 110,
    chromaCap: 130,
    segment: { minComponentArea: 30, mergeXOverlap: 4, mergeYGap: 8, smallMergeGap: 2 },
  },
  {
    label: 'I luma130 strict0.5 trim0.4 xOv4',
    lumaCap: 130,
    chromaCap: 130,
    segment: {
      minComponentArea: 30,
      mergeXOverlap: 4,
      mergeYGap: 8,
      smallMergeGap: 2,
      strictOverlapRatio: 0.5,
      trimRatio: 0.4,
    },
  },
  {
    label: 'J luma110 strict0.5 trim0.4 xOv4',
    lumaCap: 110,
    chromaCap: 130,
    segment: {
      minComponentArea: 30,
      mergeXOverlap: 4,
      mergeYGap: 8,
      smallMergeGap: 2,
      strictOverlapRatio: 0.5,
      trimRatio: 0.4,
    },
  },
];

const SCORES = [0.3, 0.35, 0.4, 0.45];
const MARGINS = [0, 0.03];
const BLUR_MODES = [false, true];
const MAX_VARIANTS_PER_CHAR = 8;

function buildTemplates(
  exclude: string,
  variant: Variant,
): { char: string; bits: Uint8Array }[] {
  const collected = new Map<string, Uint8Array[]>();

  for (const name of names) {
    if (name === exclude) continue;
    const gray = grays.get(name)!;
    const bits = binarize(gray, variant.lumaCap, variant.chromaCap);
    removeSpecks(bits);
    const glyphs = glyphBitmaps(bits, variant.segment);
    const label = labels[name];
    if (glyphs.length !== label.length) continue;

    for (let i = 0; i < glyphs.length; i++) {
      const char = label[i];
      const list = collected.get(char) ?? [];
      if (list.length >= MAX_VARIANTS_PER_CHAR) continue;
      const bitmap = glyphs[i].bitmap;
      if (!list.some((v) => v.every((value, index) => value === bitmap[index]))) {
        list.push(bitmap);
      }
      collected.set(char, list);
    }
  }

  const templates: { char: string; bits: Uint8Array }[] = [];
  for (const [char, list] of collected) {
    for (const bits of list) templates.push({ char, bits });
  }
  return templates;
}

interface Report {
  correct: number;
  nulled: number;
  wrong: number;
  wrongDetails: string[];
}

const reports: { title: string; report: Report }[] = [];

for (const variant of variants) {
  const templatesByExclude = names.map((name) => buildTemplates(name, variant));
  const chars = new Set(templatesByExclude.flatMap((t) => t.map((x) => x.char)));

  for (const blurMatch of BLUR_MODES) {
    for (const minScore of SCORES) {
      for (const minMargin of MARGINS) {
        const report: Report = { correct: 0, nulled: 0, wrong: 0, wrongDetails: [] };

        for (let i = 0; i < names.length; i++) {
          const name = names[i];
          const label = labels[name];
          const expected = solveExpression(label);
          const text = readCaptchaTextWith(images.get(name)!, {
            lumaCap: variant.lumaCap,
            chromaCap: variant.chromaCap,
            segment: variant.segment,
            templates: templatesByExclude[i],
            minMatchScore: minScore,
            minMatchMargin: minMargin,
            blurMatch,
          });
          const solve = text != null && CAPTCHA_GRAMMAR.test(text)
            ? solveExpression(text)
            : null;

          if (solve != null && solve === expected) {
            report.correct++;
          } else if (solve == null) {
            report.nulled++;
          } else {
            report.wrong++;
            report.wrongDetails.push(
              `${name}: okundu="${text}" beklenen=${label} (${expected}≠${solve})`,
            );
          }
        }

        reports.push({
          title: `${variant.label} | bulanık=${blurMatch ? 1 : 0} ` +
            `skor>=${minScore} marj>=${minMargin} ` +
            `(şablon=${templatesByExclude[0].length} karakter="${[...chars].sort().join('')}"`,
          report,
        });
      }
    }
  }
}

reports.sort((a, b) => {
  if (a.report.wrong !== b.report.wrong) return a.report.wrong - b.report.wrong;
  return b.report.correct - a.report.correct;
});

console.log('en iyi 12 kombinasyon (yanlış artan → doğru azalan):');
for (const { title, report } of reports.slice(0, 12)) {
  console.log(
    `  doğru=${String(report.correct).padStart(2)} null=${String(report.nulled).padStart(2)}` +
      ` YANLIŞ=${report.wrong}  ${title}`,
  );
  for (const line of report.wrongDetails) console.log(`      ${line}`);
}

const wrongFree = reports.filter((r) => r.report.wrong === 0);
console.log(`\nyanlış=0 kombinasyon: ${wrongFree.length}/${reports.length}`);
if (wrongFree.length > 0) {
  const best = wrongFree[0];
  console.log(`en yüksek doğru: ${best.report.correct}/20 — ${best.title}`);
}

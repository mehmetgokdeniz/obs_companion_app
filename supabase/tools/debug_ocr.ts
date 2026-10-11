/// OCR boru hattı ayıklaması: eşik/kroma/birleştirme grid aramasını,
/// beklenen segment sayısına (etiket uzunluğu) kaç örnekte ulaştığına göre tarar.
///
/// deno run --config supabase/deno.json --allow-read --allow-write \
///   supabase/tools/debug_ocr.ts <örnek_dizini> [--explain]
import {
  removeSpecks,
  segment,
  type SegmentOptions,
} from '../functions/_shared/ocr.ts';

const samplesDir = Deno.args[0] ?? '.';
const explainFlag = Deno.args.includes('--explain');

const labels = JSON.parse(
  await Deno.readTextFile(`${samplesDir}/labels.json`),
) as Record<string, string>;

const LUMA_CAPS = [110, 130, 150];
const CHROMA_CAPS = [90, 130, 255];
const MIN_AREAS = [25, 30, 40];
const SMALL_MERGE_GAPS = [0, 2];
const MERGE_X_OVERLAPS = [2, 4];
const MERGE_Y_GAP = 8;

interface Sample {
  name: string;
  label: string;
  width: number;
  height: number;
  gray: Uint8Array;
  chroma: Uint8Array;
}

const samples: Sample[] = [];
for (const [name, label] of Object.entries(labels)) {
  const image = await Deno.readFile(`${samplesDir}/${name}`);
  const jpeg = await import('npm:jpeg-js');
  const { width, height, data } = jpeg.decode(image, { useTArray: true });
  const gray = new Uint8Array(width * height);
  const chroma = new Uint8Array(width * height);
  for (let i = 0; i < gray.length; i++) {
    const r = data[i * 4];
    const g = data[i * 4 + 1];
    const b = data[i * 4 + 2];
    gray[i] = Math.round(0.299 * r + 0.587 * g + 0.114 * b);
    chroma[i] = Math.max(r, g, b) - Math.min(r, g, b);
  }
  samples.push({ name, label, width, height, gray, chroma });
}

function maskOf(sample: Sample, lumaCap: number, chromaCap: number): Uint8Array {
  const mask = new Uint8Array(sample.gray.length);
  for (let i = 0; i < mask.length; i++) {
    mask[i] = sample.gray[i] <= lumaCap && sample.chroma[i] <= chromaCap ? 1 : 0;
  }
  return mask;
}

function segmentCount(
  sample: Sample,
  luma: number,
  chroma: number,
  options: SegmentOptions,
): number {
  const bits = { width: sample.width, height: sample.height, data: maskOf(sample, luma, chroma) };
  removeSpecks(bits);
  return segment(bits, options).length;
}

interface Result {
  luma: number;
  chroma: number;
  options: SegmentOptions;
  hits: number;
  detail: number[];
}

const results: Result[] = [];

for (const luma of LUMA_CAPS) {
  for (const chroma of CHROMA_CAPS) {
    for (const minArea of MIN_AREAS) {
      for (const smallMergeGap of SMALL_MERGE_GAPS) {
        for (const mergeXOverlap of MERGE_X_OVERLAPS) {
          const options: SegmentOptions = {
            minComponentArea: minArea,
            mergeXOverlap,
            mergeYGap: MERGE_Y_GAP,
            smallMergeGap,
          };
          const detail = samples.map((s) => segmentCount(s, luma, chroma, options));
          const hits = detail.filter((count, i) => count === samples[i].label.length).length;
          results.push({ luma, chroma, options, hits, detail });
        }
      }
    }
  }
}

results.sort((a, b) => b.hits - a.hits);
console.log('en iyi 10 varyant:');
for (const result of results.slice(0, 10)) {
  const o = result.options;
  const failures = result.detail
    .map((count, i) => count === samples[i].label.length ? null : samples[i].name)
    .filter((name): name is string => name != null);
  console.log(
    `luma<=${result.luma} chroma<=${result.chroma} area>=${o.minComponentArea} ` +
      `smallGap=${o.smallMergeGap} xOverlap>=${o.mergeXOverlap} ` +
      `-> ${result.hits}/${samples.length} hatalar: ${failures.join(',') || 'yok'}`,
  );
}

const perfect = results.filter((r) => r.hits === samples.length);
console.log(perfect.length > 0
  ? `20/20 varyant sayısı: ${perfect.length}`
  : '20/20 varyant yok');

const best = results[0];
console.log('detay (best): ' + best.detail.join(','));
console.log('beklenen    : ' + samples.map((s) => s.label.length).join(','));

if (explainFlag) {
  for (let i = 0; i < samples.length; i++) {
    if (best.detail[i] !== samples[i].label.length) explain(samples[i], best);
  }
} else {
  console.log('not: --explain ile uyumsuz örneklerin bileşen dökümü alınır');
}

/// Bileşen listesini ve glif gruplarını açıklar (tanılama).
function explain(sample: Sample, result: Result): void {
  const bits = {
    width: sample.width,
    height: sample.height,
    data: maskOf(sample, result.luma, result.chroma),
  };
  removeSpecks(bits);

  const seen = new Uint8Array(bits.data.length);
  const stack: number[] = [];
  const lines: string[] = [];
  for (let start = 0; start < bits.data.length; start++) {
    if (bits.data[start] === 0 || seen[start] === 1) continue;
    stack.length = 0;
    stack.push(start);
    seen[start] = 1;
    let x0 = sample.width, x1 = 0, y0 = sample.height, y1 = 0, area = 0;
    const chromas: number[] = [];
    while (stack.length > 0) {
      const index = stack.pop()!;
      area++;
      chromas.push(sample.chroma[index]);
      const x = index % sample.width;
      const y = (index / sample.width) | 0;
      if (x < x0) x0 = x;
      if (x > x1) x1 = x;
      if (y < y0) y0 = y;
      if (y > y1) y1 = y;
      for (let dy = -1; dy <= 1; dy++) {
        for (let dx = -1; dx <= 1; dx++) {
          const nx = x + dx, ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= sample.width || ny >= sample.height) continue;
          const n = ny * sample.width + nx;
          if (bits.data[n] === 1 && seen[n] === 0) {
            seen[n] = 1;
            stack.push(n);
          }
        }
      }
    }
    chromas.sort((a, b) => a - b);
    const medianChroma = chromas[Math.floor(chromas.length / 2)];
    lines.push(
      `x${x0}-${x1} y${y0}-${y1} alan=${area} kroma=${medianChroma}` +
        `${area < result.options.minComponentArea ? ' (küçük)' : ''}`,
    );
  }
  console.log(`\n${sample.name} etiket=${sample.label}`);
  for (const line of lines.sort()) console.log('  bileşen ' + line);
  const glyphs = segment(bits, result.options);
  console.log('  glifler: ' + glyphs.map((g) => `x${g.x0}-${g.x1}`).join(', '));
}

import { decode as decodeJpeg } from 'npm:jpeg-js';

import { solveExpression } from './expression.ts';
import { decodedTemplates, GRID } from './templates.ts';

/// CAPTCHA görselini şablon eşleştirmesiyle okur.
///
/// tesseract CLI edge function'da çalışmadığı için saf JS çözüm kullanılır:
/// JPEG decode -> sabit luma/kroma eşiği -> gürültü temizliği -> bileşen
/// tabanlı karakter ayırma -> 24x24 normalize -> şablonla IoU skoru.
///
/// Düşük güvenli okumayı ASLA döndürmez: eşik altı → null çağırıcı manel
/// captcha akışına geçer (yanlış tahmin, sıfırdan daha kötüdür).

/// Mürekkep eşiği: OBS CAPTCHA'sı beyaz zemin üzerine koyu rakamlar +
/// renkli gürültü (halka/nokta/dalga) taşır. Rakamlar hem koyu hem renksiz,
/// renkli gürültü ise kroma eşiğinin üstünde kalır.
/// Değerler tools/eval_ocr.ts ile gerçek örneklerde kalibre edilir.
export const LUMA_CAP = 130;
export const CHROMA_CAP = 130;

/// IoU (kesişim/birleşim) skoru bu değerin altındaysa okuma reddedilir.
/// tools/eval_ocr.ts LOO grid'inde yanlış=0 koşuluyla kalibre edildi:
/// B varyantı (luma130/chroma130/area30/xOv4) + bulanık eşleşme,
/// skor>=0.35: 2/20 otomatik doğru, 0 yanlış (geri kalanı manel akışa düşer).
export const MIN_MATCH_SCORE = 0.35;

/// En iyi ile ikinci aday arasındaki minimum fark; eşik altı belirsizliktir.
export const MIN_MATCH_MARGIN = 0;

/// OBS'in CAPTCHA biçimi: "54+3=?" — iki haneli toplam, tek haneli eklenen.
/// Bu yapıya uymayan okuma yanlış cevaba yol açabilir; null daha güvenlidir.
export const CAPTCHA_GRAMMAR = /^\d{2}[+\-*/]\d=\?$/;

/// Bağlantılı bileşen piksel sayısı bundan küçükse gürültü (nokta) sayılır.
const MIN_COMPONENT_PX = 4;

export interface GrayImage {
  width: number;
  height: number;
  /// Piksel başına 0-255 gri değer.
  data: Uint8Array;
  /// Piksel başına renk genişliği (max-min RGB); renkli gürültüyü ayırır.
  chroma: Uint8Array;
}

export interface Bits {
  width: number;
  height: number;
  /// Piksel başına 0/1 (1 = mürekkep/glif).
  data: Uint8Array;
}

export interface Glyph {
  x0: number;
  x1: number;
  y0: number;
  y1: number;
}

export function solveCaptcha(image: Uint8Array): number | null {
  try {
    const text = readCaptchaText(image);
    if (text == null || !CAPTCHA_GRAMMAR.test(text)) return null;
    return solveExpression(text);
  } catch {
    return null;
  }
}

export function readCaptchaText(image: Uint8Array): string | null {
  return readCaptchaTextWith(image, {
    lumaCap: LUMA_CAP,
    chromaCap: CHROMA_CAP,
    segment: undefined,
    templates: decodedTemplates(),
    blurMatch: true,
  });
}

/// Araçlar/eval için parametrik okuma (varsayılan boru hattının aynısı).
export function readCaptchaTextWith(
  image: Uint8Array,
  params: {
    lumaCap: number;
    chromaCap: number;
    segment?: SegmentOptions;
    templates: { char: string; bits: Uint8Array }[];
    minMatchScore?: number;
    minMatchMargin?: number;
    /// Eşleşme öncesi1 hücrelik genişletme (faz titremesine tolerans).
    blurMatch?: boolean;
  },
): string | null {
  if (params.templates.length === 0) return null;

  const gray = toGray(image);
  const bits = binarize(gray, params.lumaCap, params.chromaCap);
  removeSpecks(bits);

  const glyphs = glyphBitmaps(bits, params.segment);
  if (glyphs.length === 0 || glyphs.length > 12) return null;

  const templates = params.blurMatch
    ? params.templates.map((t) => ({ char: t.char, bits: blur3(t.bits) }))
    : params.templates;

  const minScore = params.minMatchScore ?? MIN_MATCH_SCORE;
  const minMargin = params.minMatchMargin ?? MIN_MATCH_MARGIN;
  let text = '';
  for (const { glyph, bitmap } of glyphs) {
    const query = params.blurMatch ? blur3(bitmap) : bitmap;
    const best = classify(query, templates);
    if (best == null) return null;
    if (best.score < minScore) return null;
    if (best.score - best.secondScore < minMargin) return null;
    text += best.char;
    void glyph;
  }
  return text;
}

/// 3x3 genişletme: mürekkebin komşu hücrelerini de doldurur (bulanık eşleşme).
export function blur3(bitmap: Uint8Array): Uint8Array {
  const out = new Uint8Array(bitmap.length);
  for (let y = 0; y < GRID; y++) {
    for (let x = 0; x < GRID; x++) {
      if (bitmap[y * GRID + x] === 0) continue;
      for (let dy = -1; dy <= 1; dy++) {
        const ny = y + dy;
        if (ny < 0 || ny >= GRID) continue;
        for (let dx = -1; dx <= 1; dx++) {
          const nx = x + dx;
          if (nx < 0 || nx >= GRID) continue;
          out[ny * GRID + nx] = 1;
        }
      }
    }
  }
  return out;
}

export function toGray(image: Uint8Array): GrayImage {
  const decoded = decodeJpeg(image, { useTArray: true });
  const { width, height, data } = decoded;
  const gray = new Uint8Array(width * height);
  const chroma = new Uint8Array(width * height);
  for (let i = 0; i < gray.length; i++) {
    const offset = i * 4;
    const r = data[offset];
    const g = data[offset + 1];
    const b = data[offset + 2];
    gray[i] = Math.round(0.299 * r + 0.587 * g + 0.114 * b);
    chroma[i] = Math.max(r, g, b) - Math.min(r, g, b);
  }
  return { width, height, data: gray, chroma };
}

/// Sabit luma/kroma eşiğiyle mürekkebi ayırır.
/// Rakamlar koyu (luma ≤ cap) ve renksiz (kroma ≤ cap); renkli gürültü ve
/// açık dalga desenleri bu iki koşulun en az birine takılır.
export function binarize(
  gray: GrayImage,
  lumaCap = LUMA_CAP,
  chromaCap = CHROMA_CAP,
): Bits {
  const total = gray.data.length;
  const bits = new Uint8Array(total);
  for (let i = 0; i < total; i++) {
    bits[i] = gray.data[i] <= lumaCap && gray.chroma[i] <= chromaCap ? 1 : 0;
  }
  return { width: gray.width, height: gray.height, data: bits };
}

export interface SegmentOptions {
  /// Birleşen glif grubunun alanı bundan küçükse gürültüdür (elener).
  minComponentArea: number;
  /// İki bileşenin aynı glife ait olması için yatay örtüşme (piksel).
  mergeXOverlap: number;
  /// Dikey boşluk bundan küçükse (ör. '=' barları) aynı glif sayılır.
  mergeYGap: number;
  /// Küçük parçaların gruplara eklenmesi için izin verilen yatay boşluk.
  smallMergeGap: number;
  /// Sıkı birleştirmede en dar kutuya oran minimum örtüşme (0 = kapalı).
  /// Gürültü parçasının glife kısmi örtüşmesiyle bbox'ın şişmesini engeller.
  strictOverlapRatio?: number;
  /// Grup içinde en büyük bileşenin bu oranına uymayanlar budanır (0 = kapalı).
  trimRatio?: number;
}

export const DEFAULT_SEGMENT: SegmentOptions = {
  minComponentArea: 30,
  mergeXOverlap: 4,
  mergeYGap: 8,
  smallMergeGap: 2,
  strictOverlapRatio: 0,
  trimRatio: 0,
};

interface GlyphGroup {
  glyph: Glyph;
  /// Gruba ait bileşen pikselleri (bbox içindeki gürültü DAHİL DEĞİL).
  pixels: number[];
  area: number;
  /// Grubu oluşturan orijinal bileşenler (budama için).
  members: { pixels: number[]; area: number }[];
}

/// Glif gruplarını çıkarır: bileşen çıkar → sıkı birleştir → küçük parçaları
/// yakına yapıştır → grup alanına göre ayıkla.
///
/// Sıra önemlidir: filtre ÖNCE yapılırsa '=' barları, '+' kolları ve '?'
/// parçaları (13-27 piksel) tek başlarına elenir; gruplayınca alanları
/// eşiği geçer. İnce gürültü artıkları ise gruba yapışmadan elenir.
function segmentGroups(bits: Bits, options: SegmentOptions = DEFAULT_SEGMENT): GlyphGroup[] {
  const { width, height, data } = bits;

  const groups: GlyphGroup[] = [];
  const stack: number[] = [];
  const seen = new Uint8Array(data.length);

  for (let start = 0; start < data.length; start++) {
    if (data[start] === 0 || seen[start] === 1) continue;

    stack.length = 0;
    stack.push(start);
    seen[start] = 1;
    let x0 = width;
    let x1 = 0;
    let y0 = height;
    let y1 = 0;
    const pixels: number[] = [];

    while (stack.length > 0) {
      const index = stack.pop()!;
      pixels.push(index);
      const x = index % width;
      const y = (index / width) | 0;
      if (x < x0) x0 = x;
      if (x > x1) x1 = x;
      if (y < y0) y0 = y;
      if (y > y1) y1 = y;

      for (let dy = -1; dy <= 1; dy++) {
        for (let dx = -1; dx <= 1; dx++) {
          const nx = x + dx;
          const ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
          const n = ny * width + nx;
          if (data[n] === 1 && seen[n] === 0) {
            seen[n] = 1;
            stack.push(n);
          }
        }
      }
    }

    groups.push({
      glyph: { x0, x1, y0, y1 },
      pixels,
      area: pixels.length,
      members: [{ pixels, area: pixels.length }],
    });
  }

  // 1) Sıkı birleştirme: kutuları yatayda örtüşen, dikeyde yakın parçalar.
  //    Yan yana rakamlar kutuları örtüşmediği için buraya girmez.
  const strictRatio = options.strictOverlapRatio ?? 0;
  let changed = true;
  while (changed) {
    changed = false;
    outer: for (let i = 0; i < groups.length; i++) {
      for (let j = i + 1; j < groups.length; j++) {
        const a = groups[i].glyph;
        const b = groups[j].glyph;
        const overlap = xOverlap(a, b);
        const narrowest = Math.min(a.x1 - a.x0 + 1, b.x1 - b.x0 + 1);
        const ratioOk = strictRatio <= 0 || overlap >= strictRatio * narrowest;
        if (overlap >= options.mergeXOverlap && ratioOk &&
          yGap(a, b) <= options.mergeYGap) {
          groups[i] = mergeGroups(groups[i], groups[j]);
          groups.splice(j, 1);
          changed = true;
          break outer;
        }
      }
    }
  }

  // 2) Küçük parçaları en yakın gruba yapıştır (1-2 piksel boşluk dahil).
  //    Böylece '?' kancası, '=' parçaları, '+' kolları kaybolmaz.
  if (options.smallMergeGap > 0) {
    changed = true;
    while (changed) {
      changed = false;
      outer: for (let i = 0; i < groups.length; i++) {
        if (groups[i].area >= options.minComponentArea) continue;
        for (let j = 0; j < groups.length; j++) {
          if (i === j) continue;
          if (horizontalGap(groups[i].glyph, groups[j].glyph) <= options.smallMergeGap &&
            yGap(groups[i].glyph, groups[j].glyph) <= options.mergeYGap) {
            groups[j] = mergeGroups(groups[j], groups[i]);
            groups.splice(i, 1);
            changed = true;
            break outer;
          }
        }
      }
    }
  }

  // 3) Grup alanına göre ayıkla: yapışamayan ince gürültü artıkları elenir.
  let kept = groups
    .filter((group) => group.area >= options.minComponentArea)
    .sort((a, b) => a.glyph.x0 - b.glyph.x0);

  // 4) Budama: gruptaki küçük yapışmaları at (bbox'ı glif boyutuna indirir).
  const trimRatio = options.trimRatio ?? 0;
  if (trimRatio > 0) {
    kept = kept.map((group) => {
      if (group.members.length <= 1) return group;
      const largest = Math.max(...group.members.map((member) => member.area));
      const survivors = group.members.filter((member) =>
        member.area >= trimRatio * largest
      );
      if (survivors.length === group.members.length) return group;
      const pixels = survivors.flatMap((member) => member.pixels);
      return {
        glyph: bboxOf(pixels, bits.width, bits.height),
        pixels,
        area: pixels.length,
        members: survivors,
      };
    });
  }

  return kept;
}

function bboxOf(pixels: number[], width: number, height: number): Glyph {
  let x0 = width;
  let x1 = 0;
  let y0 = height;
  let y1 = 0;
  for (const index of pixels) {
    const x = index % width;
    const y = (index / width) | 0;
    if (x < x0) x0 = x;
    if (x > x1) x1 = x;
    if (y < y0) y0 = y;
    if (y > y1) y1 = y;
  }
  return { x0, x1, y0, y1 };
}

export function segment(bits: Bits, options: SegmentOptions = DEFAULT_SEGMENT): Glyph[] {
  return segmentGroups(bits, options).map((group) => group.glyph);
}

/// Glifin YALNIZCA kendi bileşen piksellerinden GRID x GRID bit dizisi.
///
/// bbox yerine bileşen pikselleri kullanılır: bbox'a yayılan gürültü
/// noktaları şablon eşleşmesinin IoU skorunu aşağı çekerdi.
///
/// Ölçekleme alan-kapsaması (any-ink) yapılır: bir kaynak pikselin
/// değdiği TÜM hedef hücreler doldurulur. En-komşu ölçekleme ince
/// çizgileri hücre fazına böler (14px genişlikte 2px çizgi1-3-5.
/// hücrelere düşer), farklı örneklerde faz kayınca IoU çöker.
export function glyphBitmaps(
  bits: Bits,
  options: SegmentOptions = DEFAULT_SEGMENT,
): { glyph: Glyph; bitmap: Uint8Array }[] {
  const { width } = bits;
  return segmentGroups(bits, options).map(({ glyph, pixels }) => {
    const gw = glyph.x1 - glyph.x0 + 1;
    const gh = glyph.y1 - glyph.y0 + 1;
    const bitmap = new Uint8Array(GRID * GRID);
    for (const index of pixels) {
      const x = index % width;
      const y = (index / width) | 0;
      const lx = x - glyph.x0;
      const ly = y - glyph.y0;
      const gx0 = Math.floor((lx * GRID) / gw);
      const gx1 = Math.min(GRID - 1, Math.ceil(((lx + 1) * GRID) / gw) - 1);
      const gy0 = Math.floor((ly * GRID) / gh);
      const gy1 = Math.min(GRID - 1, Math.ceil(((ly + 1) * GRID) / gh) - 1);
      for (let gy = Math.max(0, gy0); gy <= gy1; gy++) {
        for (let gx = Math.max(0, gx0); gx <= gx1; gx++) {
          bitmap[gy * GRID + gx] = 1;
        }
      }
    }
    return { glyph, bitmap };
  });
}

function mergeGroups(a: GlyphGroup, b: GlyphGroup): GlyphGroup {
  return {
    glyph: union(a.glyph, b.glyph),
    pixels: a.pixels.concat(b.pixels),
    area: a.area + b.area,
    members: a.members.concat(b.members),
  };
}

function xOverlap(a: Glyph, b: Glyph): number {
  return Math.min(a.x1, b.x1) - Math.max(a.x0, b.x0);
}

/// Kutular arasındaki yatay boşluk; örtüşüyorlarsa 0.
function horizontalGap(a: Glyph, b: Glyph): number {
  return Math.max(0, Math.max(a.x0, b.x0) - Math.min(a.x1, b.x1));
}

/// Kutular arasındaki dikey boşluk; örtüşüyorlarsa negatif.
function yGap(a: Glyph, b: Glyph): number {
  return Math.max(a.y0, b.y0) - Math.min(a.y1, b.y1);
}

function union(a: Glyph, b: Glyph): Glyph {
  return {
    x0: Math.min(a.x0, b.x0),
    x1: Math.max(a.x1, b.x1),
    y0: Math.min(a.y0, b.y0),
    y1: Math.max(a.y1, b.y1),
  };
}

/// Bağlantılı bileşenle küçük nokta gürültüsünü siler.
export function removeSpecks(bits: Bits): void {
  const { width, height, data } = bits;
  const visited = new Uint8Array(data.length);
  const stack: number[] = [];

  for (let start = 0; start < data.length; start++) {
    if (data[start] === 0 || visited[start] === 1) continue;

    stack.length = 0;
    stack.push(start);
    visited[start] = 1;
    const component: number[] = [];

    while (stack.length > 0) {
      const index = stack.pop()!;
      component.push(index);
      const x = index % width;
      const y = (index / width) | 0;
      for (let dy = -1; dy <= 1; dy++) {
        for (let dx = -1; dx <= 1; dx++) {
          const nx = x + dx;
          const ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
          const n = ny * width + nx;
          if (data[n] === 1 && visited[n] === 0) {
            visited[n] = 1;
            stack.push(n);
          }
        }
      }
    }

    if (component.length < MIN_COMPONENT_PX) {
      for (const index of component) data[index] = 0;
    }
  }
}

function iou(a: Uint8Array, b: Uint8Array): number {
  let intersection = 0;
  let union = 0;
  for (let i = 0; i < a.length; i++) {
    if (a[i] === 1 || b[i] === 1) union++;
    if (a[i] === 1 && b[i] === 1) intersection++;
  }
  return union === 0 ? 0 : intersection / union;
}

function classify(
  bitmap: Uint8Array,
  templates: { char: string; bits: Uint8Array }[],
): { char: string; score: number; secondScore: number } | null {
  let bestChar = '';
  let bestScore = -1;
  let secondScore = -1;
  for (const template of templates) {
    const score = iou(bitmap, template.bits);
    if (score > bestScore) {
      secondScore = bestScore;
      bestScore = score;
      bestChar = template.char;
    } else if (score > secondScore) {
      secondScore = score;
    }
  }
  return bestScore < 0
    ? null
    : { char: bestChar, score: bestScore, secondScore: Math.max(0, secondScore) };
}

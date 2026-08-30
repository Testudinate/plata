const pptxgen = require('pptxgenjs');
const { iconPng } = require('./icons');
const { ru, en } = require('./content');

const NAVY = '1E2761';
const NAVY_CARD = '2A3570';
const ICE = 'CADCFC';
const WHITE = 'FFFFFF';
const AMBER = 'E8A33D';
const SLATE = '333333';
const MUTED = '666666';
const LIGHT_TINT = 'EEF1FA';
const AMBER_TINT = 'FBEFDC';
const BORDER = 'DEE3F2';
const CARD_SHADOW = { type: 'outer', color: '1E2761', opacity: 0.18, blur: 6, offset: 2, angle: 90 };

async function buildIconSet() {
  const need = [
    ['FiDatabase', WHITE], ['FiEye', WHITE], ['FiCpu', WHITE],
    ['FiTarget', WHITE], ['FiLock', WHITE], ['FiUserCheck', WHITE], ['FiBell', WHITE],
    ['FiAlertTriangle', NAVY], ['FiCheckCircle', NAVY], ['FiCalendar', WHITE],
    ['FiUsers', NAVY], ['FiCheckSquare', NAVY], ['FiRefreshCw', NAVY], ['FiActivity', WHITE],
    ['FiLayers', WHITE], ['FiUserCheck', NAVY],
  ];
  const cache = {};
  for (const [name, color] of need) {
    cache[name + '_' + color] = await iconPng(name, color, 256);
  }
  return cache;
}

function addKicker(slide, text, opts = {}) {
  slide.addText(text, Object.assign({
    x: 0.6, y: 0.4, w: 10.5, h: 0.32, fontFace: 'Calibri', fontSize: 11.5, bold: true,
    color: AMBER, charSpacing: 1.5, margin: 0,
  }, opts));
}

function addTitle(slide, text, opts = {}) {
  slide.addText(text, Object.assign({
    x: 0.6, y: 0.74, w: 11.6, h: 0.85, fontFace: 'Bookman Old Style', fontSize: 25, bold: true,
    color: NAVY, margin: 0, valign: 'top', lineSpacing: 29,
  }, opts));
}

function iconCircle(slide, icons, iconName, iconColor, cx, cy, d, circleColor) {
  slide.addShape('ellipse', { x: cx, y: cy, w: d, h: d, fill: { color: circleColor }, line: { type: 'none' } });
  const pad = d * 0.26;
  slide.addImage({ data: icons[iconName + '_' + iconColor], x: cx + pad / 2, y: cy + pad / 2, w: d - pad, h: d - pad });
}

// ---- table helper -----------------------------------------------------
function styledTable(headers, rows, opts = {}) {
  const fontSize = opts.fontSize || 11;
  const sumRows = opts.sumRows || [];
  const align = opts.align || headers.map(() => 'left');
  const headerRow = headers.map((h, i) => ({
    text: h,
    options: { bold: true, color: WHITE, fill: { color: NAVY }, fontSize: fontSize + 0.5, valign: 'middle', align: align[i], fontFace: 'Calibri' },
  }));
  const bodyRows = rows.map((r, ri) => {
    const isSum = sumRows.includes(ri);
    const fill = isSum ? AMBER_TINT : (ri % 2 === 0 ? WHITE : LIGHT_TINT);
    const color = isSum ? NAVY : SLATE;
    return r.map((cellText, ci) => ({
      text: cellText,
      options: { fill: { color: fill }, color, bold: !!isSum, fontSize, valign: 'middle', align: align[ci], fontFace: 'Calibri' },
    }));
  });
  return [headerRow, ...bodyRows];
}

function addTable(slide, headers, rows, x, y, w, colW, rowH, opts = {}) {
  const data = styledTable(headers, rows, opts);
  slide.addTable(data, {
    x, y, w, colW, rowH,
    border: { type: 'solid', color: BORDER, pt: 0.5 },
    autoPage: false,
    margin: [3, 8, 3, 8],
  });
}

async function buildDeck(content, outPath) {
  const icons = await buildIconSet();
  const pres = new pptxgen();
  pres.layout = 'LAYOUT_WIDE'; // 13.3 x 7.5
  pres.theme = { headFontFace: content.fontHeader, bodyFontFace: content.fontBody };

  // ---------- Slide: Title ----------
  {
    const c = content.title;
    const s = pres.addSlide();
    s.background = { color: NAVY };
    s.addText(c.kicker, { x: 0.6, y: 0.55, w: 10, h: 0.35, fontFace: 'Calibri', fontSize: 12, bold: true, color: AMBER, charSpacing: 1.5, margin: 0 });
    s.addText(c.title, { x: 0.6, y: 1.05, w: 11.6, h: 1.85, fontFace: content.fontHeader, fontSize: 32, bold: true, color: WHITE, margin: 0, lineSpacing: 38 });
    s.addText(c.sub, { x: 0.6, y: 3.05, w: 9.6, h: 1.05, fontFace: 'Calibri', fontSize: 14, color: ICE, margin: 0, lineSpacing: 19 });

    const stats = c.stats;
    const gap = 0.28, cardW = (12.3 - gap * (stats.length - 1)) / stats.length, cardH = 1.85, y0 = 4.45;
    stats.forEach((st, i) => {
      const x = 0.6 + i * (cardW + gap);
      s.addShape('roundRect', { x, y: y0, w: cardW, h: cardH, rectRadius: 0.08, fill: { color: NAVY_CARD }, line: { type: 'none' } });
      s.addText(st.n, { x, y: y0 + 0.22, w: cardW, h: 0.6, align: 'center', fontFace: content.fontHeader, fontSize: 24, bold: true, color: WHITE, margin: 0 });
      s.addText(st.l, { x: x + 0.12, y: y0 + 0.92, w: cardW - 0.24, h: 0.85, align: 'center', fontFace: 'Calibri', fontSize: 10.5, color: ICE, margin: 0, lineSpacing: 13 });
    });
  }

  // ---------- Slide: The problem ----------
  {
    const c = content.problem;
    const s = pres.addSlide();
    s.background = { color: WHITE };
    addKicker(s, c.kicker);
    addTitle(s, c.title);
    s.addText(c.intro, { x: 0.6, y: 1.62, w: 11.5, h: 0.8, fontFace: 'Calibri', fontSize: 13.5, color: SLATE, margin: 0, lineSpacing: 17 });

    const cards = c.cards;
    const gap = 0.3, cardW = (11.3 - gap * (cards.length - 1)) / cards.length, cardH = 1.55, y0 = 2.6;
    cards.forEach((cd, i) => {
      const x = 0.6 + i * (cardW + gap);
      const isLast = i === cards.length - 1;
      s.addShape('roundRect', { x, y: y0, w: cardW, h: cardH, rectRadius: 0.08, fill: { color: isLast ? NAVY : LIGHT_TINT }, line: { type: 'none' }, shadow: Object.assign({}, CARD_SHADOW) });
      if (isLast) iconCircle(s, icons, 'FiCheckCircle', NAVY, x + cardW - 0.55, y0 + 0.16, 0.4, AMBER);
      s.addText(cd.label, { x: x + 0.15, y: y0 + 0.18, w: cardW - 0.3, h: 0.45, align: 'center', fontFace: 'Calibri', fontSize: 12, bold: true, color: isLast ? ICE : MUTED, margin: 0 });
      s.addText(cd.value, { x: x + 0.1, y: y0 + 0.65, w: cardW - 0.2, h: 0.75, align: 'center', fontFace: content.fontHeader, fontSize: 28, bold: true, color: isLast ? WHITE : NAVY, margin: 0 });
    });

    const cy = 4.35;
    s.addShape('roundRect', { x: 0.6, y: cy, w: 11.3, h: 1.55, rectRadius: 0.08, fill: { color: AMBER_TINT }, line: { type: 'none' } });
    iconCircle(s, icons, 'FiAlertTriangle', NAVY, 0.88, cy + 0.22, 0.5, WHITE);
    s.addText(c.callout, { x: 1.65, y: cy + 0.14, w: 10.05, h: 1.28, fontFace: 'Calibri', fontSize: 12.5, color: SLATE, margin: 0, lineSpacing: 16, valign: 'middle' });

    s.addText(c.source, { x: 0.6, y: 6.15, w: 11.3, h: 0.5, italic: true, fontFace: 'Calibri', fontSize: 11, color: MUTED, margin: 0, lineSpacing: 14 });
  }

  // ---------- Slide: The bridge ----------
  {
    const c = content.bridge;
    const s = pres.addSlide();
    s.background = { color: WHITE };
    addKicker(s, c.kicker);
    addTitle(s, c.title);
    s.addText(c.intro, { x: 0.6, y: 1.62, w: 11.5, h: 0.7, fontFace: 'Calibri', fontSize: 12.5, color: SLATE, margin: 0, lineSpacing: 16 });

    addTable(s, c.headers, c.rows, 0.6, 2.35, 11.3, [7.3, 2.0, 2.0], 0.375,
      { fontSize: 11, sumRows: c.sumRows, align: ['left', 'right', 'right'] });

    s.addText(c.note, { x: 0.6, y: 6.35, w: 11.3, h: 0.9, italic: true, fontFace: 'Calibri', fontSize: 11, color: MUTED, margin: 0, lineSpacing: 14 });
  }

  // ---------- Slide: Risk register ----------
  {
    const c = content.riskRegister;
    const s = pres.addSlide();
    s.background = { color: WHITE };
    addKicker(s, c.kicker);
    addTitle(s, c.title);

    addTable(s, c.headers, c.rows, 0.6, 1.8, 11.3, [0.6, 2.5, 2.3, 5.9], [0.4, 0.78, 0.78, 0.78, 0.78, 0.78, 0.78],
      { fontSize: 10.5, align: ['center', 'left', 'left', 'left'] });

    s.addText(c.note, { x: 0.6, y: 6.95, w: 11.3, h: 0.4, italic: true, fontFace: 'Calibri', fontSize: 11, color: MUTED, margin: 0 });
  }

  // ---------- Slide: Ownership ----------
  {
    const c = content.ownership;
    const s = pres.addSlide();
    s.background = { color: WHITE };
    addKicker(s, c.kicker);
    addTitle(s, c.title);

    addTable(s, c.headers, c.rows, 0.6, 1.85, 11.3, [3.0, 8.3], [0.4, 0.85, 0.85, 0.85],
      { fontSize: 12.5, align: ['left', 'left'] });

    const cy = 5.0;
    s.addShape('roundRect', { x: 0.6, y: cy, w: 11.3, h: 1.75, rectRadius: 0.08, fill: { color: AMBER_TINT }, line: { type: 'none' } });
    iconCircle(s, icons, 'FiUserCheck', NAVY, 0.88, cy + 0.2, 0.48, WHITE);
    s.addText(c.calloutTitle, { x: 1.65, y: cy + 0.14, w: 10.05, h: 0.35, fontFace: content.fontHeader, fontSize: 13.5, bold: true, color: NAVY, margin: 0 });
    s.addText(c.callout, { x: 1.65, y: cy + 0.55, w: 10.05, h: 1.15, fontFace: 'Calibri', fontSize: 12, color: SLATE, margin: 0, lineSpacing: 15.5 });
  }

  // ---------- Slide: The proof ----------
  {
    const c = content.proof;
    const s = pres.addSlide();
    s.background = { color: WHITE };
    addKicker(s, c.kicker);
    addTitle(s, c.title);

    const bullets = c.bullets;
    const rowH = 1.5, y0 = 1.95;
    bullets.forEach((b, i) => {
      const y = y0 + i * rowH;
      iconCircle(s, icons, b.icon, WHITE, 0.6, y, 0.55, NAVY);
      s.addText(b.text, { x: 1.35, y: y - 0.08, w: 6.75, h: 1.3, fontFace: 'Calibri', fontSize: 13.5, color: SLATE, margin: 0, lineSpacing: 17, valign: 'top' });
    });

    s.addShape('roundRect', { x: 8.35, y: 1.95, w: 3.55, h: 4.35, rectRadius: 0.1, fill: { color: NAVY }, line: { type: 'none' } });
    s.addText(c.costBig, { x: 8.35, y: 3.0, w: 3.55, h: 1.05, align: 'center', fontFace: content.fontHeader, fontSize: 56, bold: true, color: AMBER, margin: 0 });
    s.addText(c.costLabel, { x: 8.65, y: 4.15, w: 2.95, h: 1.1, align: 'center', fontFace: 'Calibri', fontSize: 12, color: ICE, margin: 0, lineSpacing: 15 });
  }

  // ---------- Slide: The fix ----------
  {
    const c = content.fix;
    const s = pres.addSlide();
    s.background = { color: WHITE };
    addKicker(s, c.kicker);
    addTitle(s, c.title);

    const cards = c.cards;
    const cols = 2, gapX = 0.3, gapY = 0.2, cardW = (11.3 - gapX) / cols, cardH = 1.55, y0 = 1.75;
    cards.forEach((cd, i) => {
      const col = i % cols, row = Math.floor(i / cols);
      const x = 0.6 + col * (cardW + gapX), y = y0 + row * (cardH + gapY);
      s.addShape('roundRect', { x, y, w: cardW, h: cardH, rectRadius: 0.08, fill: { color: WHITE }, line: { color: LIGHT_TINT, width: 1 }, shadow: Object.assign({}, CARD_SHADOW) });
      iconCircle(s, icons, cd.icon, WHITE, x + 0.26, y + 0.24, 0.46, NAVY);
      s.addText(cd.title, { x: x + 0.88, y: y + 0.22, w: cardW - 1.1, h: 0.45, fontFace: content.fontHeader, fontSize: 14, bold: true, color: NAVY, margin: 0, valign: 'middle' });
      s.addText(cd.text, { x: x + 0.26, y: y + 0.76, w: cardW - 0.52, h: 0.72, fontFace: 'Calibri', fontSize: 11, color: SLATE, margin: 0, lineSpacing: 13.5 });
    });

    const codeY = y0 + 2 * (cardH + gapY) + 0.05;
    s.addShape('roundRect', { x: 0.6, y: codeY, w: 11.3, h: 0.8, rectRadius: 0.06, fill: { color: NAVY }, line: { type: 'none' } });
    s.addText(c.codeLabel, { x: 0.85, y: codeY + 0.07, w: 10.8, h: 0.28, fontFace: 'Calibri', fontSize: 10, color: ICE, margin: 0 });
    s.addText(c.codeExample, { x: 0.85, y: codeY + 0.37, w: 10.8, h: 0.38, fontFace: 'Courier New', fontSize: 11.5, color: AMBER, margin: 0 });

    s.addText(c.gate, { x: 0.6, y: codeY + 0.92, w: 11.3, h: 0.95, italic: true, fontFace: 'Calibri', fontSize: 10.5, color: MUTED, margin: 0, lineSpacing: 13 });
  }

  // ---------- Slide: Maturity ladder ----------
  {
    const c = content.maturity;
    const s = pres.addSlide();
    s.background = { color: WHITE };
    addKicker(s, c.kicker);
    addTitle(s, c.title);

    addTable(s, c.headers, c.rows, 0.6, 1.85, 11.3, [2.7, 2.9, 5.7], [0.4, 0.85, 0.85, 0.85, 0.85],
      { fontSize: 11.5, align: ['left', 'left', 'left'] });

    s.addShape('roundRect', { x: 0.6, y: 5.85, w: 11.3, h: 1.15, rectRadius: 0.08, fill: { color: LIGHT_TINT }, line: { type: 'none' } });
    s.addText(c.legend, { x: 0.9, y: 5.85, w: 10.7, h: 1.15, valign: 'middle', fontFace: 'Calibri', fontSize: 11.5, color: SLATE, margin: 0, lineSpacing: 15 });
  }

  // ---------- Slide: Checks & drift signals ----------
  {
    const c = content.checks;
    const s = pres.addSlide();
    s.background = { color: WHITE };
    addKicker(s, c.kicker);
    addTitle(s, c.title);

    addTable(s, c.headers, c.rows, 0.6, 1.85, 11.3, [3.3, 8.0], 0.65,
      { fontSize: 11.5, align: ['left', 'left'] });

    const stats = c.stats;
    const gap = 0.3, cardW = (11.3 - gap) / 2, cardH = 1.0, y0 = 4.65;
    stats.forEach((st, i) => {
      const x = 0.6 + i * (cardW + gap);
      s.addShape('roundRect', { x, y: y0, w: cardW, h: cardH, rectRadius: 0.08, fill: { color: NAVY_CARD }, line: { type: 'none' } });
      s.addText(st.n, { x: x + 0.2, y: y0, w: 2.4, h: cardH, valign: 'middle', fontFace: content.fontHeader, fontSize: 24, bold: true, color: WHITE, margin: 0 });
      s.addText(st.l, { x: x + 2.6, y: y0, w: cardW - 2.8, h: cardH, valign: 'middle', fontFace: 'Calibri', fontSize: 11, color: ICE, margin: 0, lineSpacing: 13 });
    });

    const cy = 5.85;
    s.addShape('roundRect', { x: 0.6, y: cy, w: 11.3, h: 1.4, rectRadius: 0.08, fill: { color: AMBER_TINT }, line: { type: 'none' } });
    iconCircle(s, icons, 'FiCheckSquare', NAVY, 0.88, cy + 0.18, 0.44, WHITE);
    s.addText(c.calloutTitle, { x: 1.6, y: cy + 0.1, w: 10.1, h: 0.35, fontFace: content.fontHeader, fontSize: 13, bold: true, color: NAVY, margin: 0 });
    s.addText(c.callout, { x: 1.6, y: cy + 0.48, w: 10.1, h: 0.85, fontFace: 'Calibri', fontSize: 11, color: SLATE, margin: 0, lineSpacing: 13.5 });
  }

  // ---------- Slide: AI agent ----------
  {
    const c = content.agent;
    const s = pres.addSlide();
    s.background = { color: WHITE };
    addKicker(s, c.kicker);
    addTitle(s, c.title);

    const leftX = 0.6, leftW = 5.5, rightX = 6.4, rightW = 5.5, topY = 1.75;
    s.addText(c.archSubhead, { x: leftX, y: topY, w: leftW, h: 0.35, fontFace: content.fontHeader, fontSize: 13.5, bold: true, color: NAVY, margin: 0 });
    const rowH = 0.82;
    c.arch.forEach((line, i) => {
      const y = topY + 0.45 + i * rowH;
      iconCircle(s, icons, 'FiCpu', WHITE, leftX, y, 0.42, NAVY);
      s.addText(line, { x: leftX + 0.6, y: y - 0.05, w: leftW - 0.6, h: rowH, fontFace: 'Calibri', fontSize: 11, color: SLATE, margin: 0, lineSpacing: 14, valign: 'top' });
    });
    const ctxY = topY + 0.45 + c.arch.length * rowH + 0.1;
    s.addShape('roundRect', { x: leftX, y: ctxY, w: leftW, h: 0.95, rectRadius: 0.08, fill: { color: LIGHT_TINT }, line: { type: 'none' } });
    s.addText(c.contextLabel, { x: leftX + 0.25, y: ctxY, w: leftW - 0.5, h: 0.95, valign: 'middle', fontFace: 'Calibri', fontSize: 11, color: SLATE, margin: 0, lineSpacing: 14 });

    s.addText(c.evalSubhead, { x: rightX, y: topY, w: rightW, h: 0.35, fontFace: content.fontHeader, fontSize: 13.5, bold: true, color: NAVY, margin: 0 });
    addTable(s, c.evalHeaders, c.evalRows, rightX, topY + 0.45, rightW, [1.5, 0.7, 3.3], [0.42, 0.95, 0.95, 0.95],
      { fontSize: 9.7, align: ['center', 'center', 'left'] });

    const trustY = 6.0;
    s.addShape('roundRect', { x: 0.6, y: trustY, w: 11.3, h: 1.05, rectRadius: 0.08, fill: { color: NAVY }, line: { type: 'none' } });
    s.addText(c.trust, { x: 0.9, y: trustY, w: 10.7, h: 1.05, valign: 'middle', fontFace: 'Calibri', fontSize: 11.5, color: ICE, margin: 0, lineSpacing: 15 });
  }

  // ---------- Slide: AI gaps ----------
  {
    const c = content.aiGaps;
    const s = pres.addSlide();
    s.background = { color: WHITE };
    addKicker(s, c.kicker);
    addTitle(s, c.title);

    const leftX = 0.6, leftW = 5.5, rightX = 6.4, rightW = 5.5, topY = 1.75;
    s.addText(c.archSubhead, { x: leftX, y: topY, w: leftW, h: 0.35, fontFace: content.fontHeader, fontSize: 13.5, bold: true, color: NAVY, margin: 0 });
    const rowH = 1.05;
    c.arch.forEach((line, i) => {
      const y = topY + 0.45 + i * rowH;
      iconCircle(s, icons, 'FiAlertTriangle', NAVY, leftX, y, 0.42, LIGHT_TINT);
      s.addText(line, { x: leftX + 0.6, y: y - 0.05, w: leftW - 0.6, h: rowH, fontFace: 'Calibri', fontSize: 11, color: SLATE, margin: 0, lineSpacing: 14, valign: 'top' });
    });

    s.addText(c.evalSubhead, { x: rightX, y: topY, w: rightW, h: 0.35, fontFace: content.fontHeader, fontSize: 13.5, bold: true, color: NAVY, margin: 0 });
    addTable(s, c.evalHeaders, c.evalRows, rightX, topY + 0.45, rightW, [2.0, 3.5], [0.4, 0.75, 0.75, 0.75, 0.75],
      { fontSize: 10, align: ['left', 'left'] });

    const noteY = 6.0;
    s.addShape('roundRect', { x: 0.6, y: noteY, w: 11.3, h: 1.05, rectRadius: 0.08, fill: { color: NAVY }, line: { type: 'none' } });
    s.addText(c.note, { x: 0.9, y: noteY, w: 10.7, h: 1.05, valign: 'middle', fontFace: 'Calibri', fontSize: 11.5, color: ICE, margin: 0, lineSpacing: 15 });
  }

  // ---------- Slide: Change management ----------
  {
    const c = content.change;
    const s = pres.addSlide();
    s.background = { color: WHITE };
    addKicker(s, c.kicker);
    addTitle(s, c.title);
    s.addText(c.intro, { x: 0.6, y: 1.62, w: 11.5, h: 0.95, fontFace: 'Calibri', fontSize: 12.5, color: SLATE, margin: 0, lineSpacing: 16 });

    addTable(s, c.headers, c.rows, 0.6, 2.75, 11.3, [3.3, 1.8, 6.2], 0.62,
      { fontSize: 11, align: ['left', 'center', 'left'] });

    const cy = 6.05;
    s.addShape('roundRect', { x: 0.6, y: cy, w: 11.3, h: 0.85, rectRadius: 0.08, fill: { color: LIGHT_TINT }, line: { type: 'none' } });
    iconCircle(s, icons, 'FiRefreshCw', NAVY, 0.85, cy + 0.17, 0.5, WHITE);
    s.addText(c.rollback, { x: 1.6, y: cy, w: 10.1, h: 0.85, valign: 'middle', fontFace: 'Calibri', fontSize: 11.5, color: SLATE, margin: 0, lineSpacing: 14 });
  }

  // ---------- Slide: Change management ladder ----------
  {
    const c = content.changeLadder;
    const s = pres.addSlide();
    s.background = { color: WHITE };
    addKicker(s, c.kicker);
    addTitle(s, c.title);

    addTable(s, c.headers, c.rows, 0.6, 1.9, 11.3, [1.9, 9.4], [0.4, 0.95, 0.95, 0.95, 0.95],
      { fontSize: 12, align: ['left', 'left'] });

    s.addShape('roundRect', { x: 0.6, y: 6.15, w: 11.3, h: 1.0, rectRadius: 0.08, fill: { color: LIGHT_TINT }, line: { type: 'none' } });
    s.addText(c.note, { x: 0.9, y: 6.15, w: 10.7, h: 1.0, valign: 'middle', fontFace: 'Calibri', fontSize: 11.5, color: SLATE, margin: 0, lineSpacing: 15 });
  }

  // ---------- Slide: Why these two dimensions ----------
  {
    const c = content.plan90;
    const s = pres.addSlide();
    s.background = { color: WHITE };
    addKicker(s, c.kicker);
    addTitle(s, c.title);

    const leftX = 0.6, leftW = 6.6, rightX = 7.5, rightW = 4.4, topY = 1.75;
    s.addText(c.reasoning, { x: leftX, y: topY, w: leftW, h: 1.35, fontFace: 'Calibri', fontSize: 12, color: SLATE, margin: 0, lineSpacing: 15.5 });
    s.addText(c.measureSubhead, { x: leftX, y: topY + 1.45, w: leftW, h: 0.32, fontFace: content.fontHeader, fontSize: 13, bold: true, color: NAVY, margin: 0 });
    const measuresText = c.measures.map(m => '–  ' + m).join('\n');
    s.addText(measuresText, { x: leftX, y: topY + 1.8, w: leftW, h: 1.9, fontFace: 'Calibri', fontSize: 11.5, color: SLATE, margin: 0, lineSpacing: 19 });

    s.addShape('roundRect', { x: rightX, y: topY, w: rightW, h: 3.9, rectRadius: 0.08, fill: { color: AMBER_TINT }, line: { type: 'none' } });
    s.addText(c.notPrioritySubhead, { x: rightX + 0.25, y: topY + 0.2, w: rightW - 0.5, h: 0.55, fontFace: content.fontHeader, fontSize: 13, bold: true, color: NAVY, margin: 0, lineSpacing: 16 });
    const notPriorityText = c.notPriority.map(m => '–  ' + m).join('\n\n');
    s.addText(notPriorityText, { x: rightX + 0.25, y: topY + 0.8, w: rightW - 0.5, h: 3.0, fontFace: 'Calibri', fontSize: 10.5, color: SLATE, margin: 0, lineSpacing: 14 });
  }

  // ---------- Slide: The plan ----------
  {
    const c = content.plan;
    const s = pres.addSlide();
    s.background = { color: WHITE };
    addKicker(s, c.kicker);
    addTitle(s, c.title);

    const steps = c.steps;
    const colW = 11.3 / steps.length;
    const nodeD = 0.95, nodeY = 2.15, lineY = nodeY + nodeD / 2 - 0.015;
    const centers = steps.map((_, i) => 0.6 + colW * i + colW / 2);

    s.addShape('rect', { x: centers[0], y: lineY, w: centers[centers.length - 1] - centers[0], h: 0.03, fill: { color: ICE }, line: { type: 'none' } });

    steps.forEach((st, i) => {
      const cx = centers[i];
      s.addShape('ellipse', { x: cx - nodeD / 2, y: nodeY, w: nodeD, h: nodeD, fill: { color: NAVY }, line: { color: WHITE, width: 3 } });
      s.addText(String(i + 1), { x: cx - nodeD / 2, y: nodeY, w: nodeD, h: nodeD, align: 'center', valign: 'middle', fontFace: content.fontHeader, fontSize: 24, bold: true, color: AMBER, margin: 0 });

      const cardX = 0.6 + colW * i + 0.15, cardW = colW - 0.3, cardY = nodeY + nodeD + 0.3, cardH = 2.6;
      s.addShape('roundRect', { x: cardX, y: cardY, w: cardW, h: cardH, rectRadius: 0.08, fill: { color: LIGHT_TINT }, line: { type: 'none' } });
      s.addText(st.day, { x: cardX + 0.2, y: cardY + 0.2, w: cardW - 0.4, h: 0.4, fontFace: content.fontHeader, fontSize: 14, bold: true, color: NAVY, margin: 0 });
      s.addText(st.text, { x: cardX + 0.2, y: cardY + 0.65, w: cardW - 0.4, h: cardH - 0.85, fontFace: 'Calibri', fontSize: 12, color: SLATE, margin: 0, lineSpacing: 15.5 });
    });
  }

  // ---------- Slide: Team ----------
  {
    const c = content.team;
    const s = pres.addSlide();
    s.background = { color: WHITE };
    addKicker(s, c.kicker);
    addTitle(s, c.title);

    const cards = c.cards;
    const gap = 0.3, cardW = (11.3 - gap) / 2, cardH = 2.15, y0 = 1.95;
    cards.forEach((cd, i) => {
      const x = 0.6 + i * (cardW + gap);
      s.addShape('roundRect', { x, y: y0, w: cardW, h: cardH, rectRadius: 0.08, fill: { color: LIGHT_TINT }, line: { type: 'none' } });
      s.addText(cd.title, { x: x + 0.3, y: y0 + 0.25, w: cardW - 0.6, h: 0.45, fontFace: content.fontHeader, fontSize: 18, bold: true, color: NAVY, margin: 0 });
      s.addText(cd.subtitle, { x: x + 0.3, y: y0 + 0.72, w: cardW - 0.6, h: 0.35, fontFace: 'Calibri', fontSize: 12.5, bold: true, color: AMBER, margin: 0 });
      s.addText(cd.text, { x: x + 0.3, y: y0 + 1.15, w: cardW - 0.6, h: 0.9, fontFace: 'Calibri', fontSize: 12.5, color: SLATE, margin: 0, lineSpacing: 16 });
    });

    const principles = c.principles;
    const py0 = 4.5, prowH = 0.68;
    principles.forEach((p, i) => {
      const y = py0 + i * prowH;
      iconCircle(s, icons, 'FiUsers', NAVY, 0.6, y, 0.42, LIGHT_TINT);
      s.addText(p, { x: 1.2, y: y - 0.05, w: 10.7, h: 0.55, fontFace: 'Calibri', fontSize: 13.5, color: SLATE, margin: 0, valign: 'middle' });
    });
  }

  // ---------- Slide: Assumptions ----------
  {
    const c = content.assumptions;
    const s = pres.addSlide();
    s.background = { color: WHITE };
    addKicker(s, c.kicker);
    addTitle(s, c.title);

    const items = c.items;
    const y0 = 2.0, rowH = 0.92;
    items.forEach((item, i) => {
      const y = y0 + i * rowH;
      iconCircle(s, icons, 'FiCheckSquare', NAVY, 0.6, y, 0.4, LIGHT_TINT);
      s.addText(item, { x: 1.2, y: y - 0.12, w: 10.7, h: rowH, fontFace: 'Calibri', fontSize: 12.5, color: SLATE, margin: 0, lineSpacing: 16, valign: 'middle' });
    });
  }

  // ---------- Slide: Closing ----------
  {
    const c = content.closing;
    const s = pres.addSlide();
    s.background = { color: NAVY };
    s.addText(c.kicker, { x: 0.6, y: 0.7, w: 10, h: 0.35, fontFace: 'Calibri', fontSize: 12, bold: true, color: AMBER, charSpacing: 1.5, margin: 0 });
    s.addText(c.title, { x: 0.6, y: 1.2, w: 11.6, h: 1.3, fontFace: content.fontHeader, fontSize: 34, bold: true, color: WHITE, margin: 0 });
    s.addText(c.body, { x: 0.6, y: 2.75, w: 10.8, h: 1.6, fontFace: 'Calibri', fontSize: 18, color: ICE, margin: 0, lineSpacing: 25 });
    s.addText(c.footer, { x: 0.6, y: 6.75, w: 11.6, h: 0.4, fontFace: 'Calibri', fontSize: 11.5, italic: true, color: ICE, margin: 0 });
  }

  await pres.writeFile({ fileName: outPath });
  console.log('Wrote', outPath);
}

(async () => {
  await buildDeck(ru, 'plata-risk-governance-presentation-ru.pptx');
  await buildDeck(en, 'plata-risk-governance-presentation-en.pptx');
})().catch(e => { console.error(e); process.exit(1); });

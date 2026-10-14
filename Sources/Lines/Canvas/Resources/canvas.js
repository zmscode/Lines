"use strict";
const NS = "http://www.w3.org/2000/svg";
const XLINK = "http://www.w3.org/1999/xlink";
const host = document.getElementById("host");
const selBox = document.getElementById("sel");
// The corner-radius knob for a selected rectangle (see Corner radius below).
// The layer the selection, handles and document frame sit on (see render).
const overlayLayer = document.createElement("div");
overlayLayer.id = "overlay-layer";
document.body.appendChild(overlayLayer);
for (const id of ["doc", "hover", "sel", "text-editor"]) {
  const el = document.getElementById(id);
  if (el) overlayLayer.appendChild(el);
}

// Gradient handles for a selected shape (see Gradient handles below).
const gradientLine = document.createElement("div");
gradientLine.id = "gradient-line";
overlayLayer.appendChild(gradientLine);
const gradientKnobs = [0, 1].map((i) => {
  const k = document.createElement("div");
  k.className = "gradient-knob";
  k.dataset.index = i;
  overlayLayer.appendChild(k);
  return k;
});
// A clip path or mask being edited on the canvas (see below).
let defEdit = null;
// Top left, top right, bottom right, bottom left.
const radiusKnobs = [0, 1, 2, 3].map((corner) => {
  const k = document.createElement("div");
  k.className = "radius-knob";
  k.dataset.corner = corner;
  k.title = "Drag to round all corners (⌘ rounds just this one)";
  overlayLayer.appendChild(k);
  return k;
});
const hoverBox = document.getElementById("hover");
const post = (m) => window.webkit.messageHandlers.bridge.postMessage(m);

let root = null; // live <svg> element
// Text before and after the drawing's <svg>: the prolog, doctype and comments,
// or a page the drawing sits in. Kept as written.
let prefix = "";
let suffix = "\n";
let selected = null;
// Off in preview mode: the drawing can be viewed, zoomed and played, not changed.
let editable = true;
let zoom = 1; // display scale; never written to the file
let autoFit = true; // keep fitting to the window until someone zooms by hand
const MIN_ZOOM = 0.05,
  MAX_ZOOM = 64;

// MARK: Rendering

// Where the drawing is in the text: its first <svg> element, from the start
// tag to the end of its end tag.
function drawingSpan(text) {
  const tags =
    /<!--[\s\S]*?-->|<!\[CDATA\[[\s\S]*?\]\]>|<(\/?)svg(?=[\s/>])(?:[^>"']|"[^"]*"|'[^']*')*>/g;
  let start = -1;
  let depth = 0;
  let m;
  while ((m = tags.exec(text))) {
    if (m[0].startsWith("<!")) continue;
    const closing = m[1] === "/";
    const empty = !closing && m[0].endsWith("/>");
    if (start < 0) {
      if (closing) continue;
      start = m.index;
      if (empty) return { start, end: tags.lastIndex };
    } else if (closing) {
      if (depth === 0) return { start, end: tags.lastIndex };
      depth--;
    } else if (!empty) {
      depth++;
    }
  }
  return start < 0 ? null : { start, end: text.length };
}

function parseError(doc) {
  const err = doc.querySelector("parsererror");
  return err
    ? err.textContent
        .replace(/\s+/g, " ")
        .replace(/^.*?error[^:]*:\s*/i, "")
        .trim() || "This SVG couldn't be parsed."
    : null;
}

// The drawing is the root <svg>, or the first <svg> inside another root (an
// XHTML or HTML page, say); only it is shown and edited.
function setSVG(text) {
  const doc = new DOMParser().parseFromString(text, "image/svg+xml");
  let error = parseError(doc);
  const span = drawingSpan(text);
  let drawing = null;
  if (!error) {
    drawing =
      doc.documentElement.localName === "svg"
        ? doc.documentElement
        : doc.getElementsByTagNameNS(NS, "svg")[0] || null;
    // Without a span the page around it couldn't be kept.
    if (drawing && drawing !== doc.documentElement && !span) drawing = null;
  }
  if (!drawing && span) {
    // Not XML (an HTML page): read just the drawing, which in a page may lean
    // on it for its namespaces.
    let source = text.slice(span.start, span.end);
    const open = source.slice(0, source.indexOf(">"));
    if (!/\sxmlns\s*=/.test(open)) source = source.replace(/^<svg/, `<svg xmlns="${NS}"`);
    if (/\bxlink:/.test(source) && !/\sxmlns:xlink\s*=/.test(open)) {
      source = source.replace(/^<svg/, '<svg xmlns:xlink="http://www.w3.org/1999/xlink"');
    }
    const inner = new DOMParser().parseFromString(source, "image/svg+xml");
    error = parseError(inner);
    if (!error) drawing = inner.documentElement;
  }
  if (!drawing) {
    post({ type: "error", message: error || "There's no <svg> element to show." });
    return;
  }
  const oldPath = selected ? pathOf(selected) : null;
  if (span) {
    prefix = text.slice(0, span.start);
    suffix = text.slice(span.end);
  } else {
    prefix = "";
    suffix = (text.match(/\s*$/) || ["\n"])[0];
  }
  const node = document.importNode(drawing, true);
  if (defEdit) {
    defEdit = null;
    post({ type: "definitionEdit", active: false });
  }
  host.replaceChildren(node);
  root = node;
  restoreAnimationState();
  if (autoFit) {
    applyZoom(fitScale(), null, null, true);
    centerContent();
  } else {
    updateIntrinsicSize();
    clampPan();
    renderNow();
  }
  scheduleThumbnail();
  scheduleOutline();
  post({ type: "ok" });
  const restored = oldPath ? byPath(oldPath) : null;
  select(restored && restored !== root ? restored : null, true);
}

function intrinsicSize() {
  const vb = root.viewBox && root.viewBox.baseVal;
  const hasVB = vb && (vb.width > 0 || vb.height > 0);
  const len = (name) => {
    const a = root.getAttribute(name);
    if (!a || a.trim().endsWith("%")) return null;
    const v = root[name].baseVal;
    try {
      v.convertToSpecifiedUnits(1);
    } catch {}
    return v.value || null;
  };
  let w = len("width"),
    h = len("height");
  if (hasVB) {
    if (w == null && h == null) {
      w = vb.width;
      h = vb.height;
    } else if (w == null) w = (h * vb.width) / vb.height;
    else if (h == null) h = (w * vb.height) / vb.width;
  }
  return { w: w || 300, h: h || 150 };
}

function updateIntrinsicSize() {
  // Sizing goes in a stylesheet, not on the element, so it never ends up in the file.
  const { w, h } = intrinsicSize();
  document.getElementById("size").textContent =
    `#host > svg { width: ${w * zoom}px !important; height: ${h * zoom}px !important; }`;
}

function serialize() {
  // While a clip path or mask is edited on the canvas, save it as it belongs.
  if (defEdit) stashDefinitionEdit(true);
  const text = prefix + new XMLSerializer().serializeToString(root) + suffix;
  if (defEdit) stashDefinitionEdit(false);
  return text;
}

// Inside a batch (one action applied to several elements), commits wait and
// become a single undo step when the batch ends.
let batching = 0;
let batchedAction = null;
function inBatch(fn) {
  batching++;
  try {
    fn();
  } finally {
    batching--;
  }
  if (!batching && batchedAction) {
    const action = batchedAction;
    batchedAction = null;
    commit(action);
  }
}

function commit(action, coalesce) {
  if (batching) {
    batchedAction = batchedAction || action;
    return;
  }
  const svg = serialize();
  scheduleThumbnail();
  scheduleOutline();
  post({ type: "changed", svg, action, coalesce: coalesce || null });
  reportSelection(true);
}

// `color` is used by the custom background.
// With `drawingOnly`, the background fills the drawing's area and the window
// colour surrounds it.
function setBackground(kind, color, drawingOnly) {
  document.body.className = kind;
  document.body.classList.toggle("drawing-only", !!drawingOnly);
  document.body.style.setProperty("--custom", color || "#f2a65a");
  document.body.style.background = kind === "custom" && color && !drawingOnly ? color : "";
}
function setAccent(css) {
  document.documentElement.style.setProperty("--accent", css);
}

// MARK: Element addressing

function pathOf(el) {
  const path = [];
  while (el && el !== root) {
    path.unshift(Array.prototype.indexOf.call(el.parentNode.children, el));
    el = el.parentNode;
  }
  return path;
}
function byPath(path) {
  let el = root;
  for (const i of path) {
    el = el && el.children[i];
  }
  return el || null;
}
// Preorder index among all elements, matching start tags in the source.
function orderOf(el) {
  if (el === root) return 0;
  let i = 0;
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT);
  while (walker.nextNode()) {
    i++;
    if (walker.currentNode === el) return i;
  }
  return -1;
}
function byOrder(n) {
  if (n === 0) return root;
  let i = 0;
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT);
  while (walker.nextNode()) {
    if (++i === n) return walker.currentNode;
  }
  return null;
}

// MARK: Selection

const nonVisual = new Set([
  "defs",
  "style",
  "script",
  "title",
  "desc",
  "metadata",
  "linearGradient",
  "radialGradient",
  "stop",
  "pattern",
  "clipPath",
  "mask",
  "filter",
  "symbol",
  "marker",
]);

function pickTarget(t) {
  if (!root || !root.contains(t) || t === root) return null;
  // Text runs select their <text>; everything else selects the clicked leaf.
  if (t.localName === "tspan" || t.localName === "textPath") t = t.closest("text") || t;
  return t;
}

// Further elements selected with Shift-click or a marquee; `selected` stays
// the primary one the inspector shows.
let extras = [];

// Everything selected, primary first.
function selection() {
  if (!selected) return [];
  extras = extras.filter((e) => e !== selected && root && root.contains(e));
  return [selected, ...extras];
}

function select(el, fromSource) {
  if (defEdit && (!el || !defEdit.group.contains(el))) endDefinitionEdit(false);
  selected = el && el !== root ? el : null;
  extras = [];
  updateOverlay();
  reportSelection(false, fromSource);
}

// Several at once; the first becomes the primary selection.
function selectMany(els) {
  selected = els[0] || null;
  extras = els.slice(1);
  updateOverlay();
  reportSelection(false);
}

// Shift-click: add to the selection, or take it out.
function toggleSelected(el) {
  const all = selection();
  if (all.includes(el)) selectMany(all.filter((e) => e !== el));
  else selectMany([...all, el]);
}

function selectByOrder(n, fromSource) {
  const el = byOrder(n);
  if (el) select(el, fromSource);
}

function selectParent() {
  if (selected && selected.parentNode && selected.parentNode !== root) select(selected.parentNode);
  else select(null);
}

function reportSelection(afterEdit, fromSource) {
  if (!root) return;
  const el = selected || root;
  const attrs = Array.from(el.attributes).map((a) => [a.name, a.value]);
  const textual =
    el.localName === "text" ||
    el.localName === "tspan" ||
    el.localName === "title" ||
    el.localName === "desc";
  post({
    type: "selection",
    path: selected ? pathOf(el) : [],
    order: orderOf(el),
    tag: el.localName,
    attrs,
    text: textual ? el.textContent : null,
    bounds: selected ? boundsOf(el) : null,
    rotation: selected ? rotationOf(el) : 0,
    count: selection().length,
    fromSource: !!fromSource || !!afterEdit,
  });
}

// What an element covers on screen, stroke included: WebKit's boxes follow
// the geometry (a path's centre line), so a thick stroke would spill out.
function visualRect(el, depth = 0) {
  if (!el.getBoundingClientRect) return null;
  const name = el.localName;
  if ((name === "g" || name === "a" || name === "switch") && depth < 8) {
    let u = null,
      count = 0;
    for (const c of el.children) {
      if (nonVisual.has(c.localName) || ANIM_TAGS.has(c.localName)) continue;
      if (++count > 400) return el.getBoundingClientRect();
      const r = visualRect(c, depth + 1);
      if (!r || (!r.width && !r.height)) continue;
      u = u
        ? {
            left: Math.min(u.left, r.left),
            top: Math.min(u.top, r.top),
            right: Math.max(u.right, r.right),
            bottom: Math.max(u.bottom, r.bottom),
          }
        : { left: r.left, top: r.top, right: r.right, bottom: r.bottom };
    }
    return u
      ? new DOMRect(u.left, u.top, u.right - u.left, u.bottom - u.top)
      : el.getBoundingClientRect();
  }
  const r = el.getBoundingClientRect();
  if (!r.width && !r.height && name !== "line" && name !== "path" && name !== "polyline") return r;
  let cs;
  try {
    cs = getComputedStyle(el);
  } catch {
    return r;
  }
  if (!cs || !cs.stroke || cs.stroke === "none" || isHidden(el)) return r;
  const sw = parseFloat(cs.strokeWidth) || 0;
  if (!sw) return r;
  let scale = 1;
  if (cs.vectorEffect !== "non-scaling-stroke") {
    const m = el.getScreenCTM && el.getScreenCTM();
    if (m) scale = Math.sqrt(Math.abs(m.a * m.d - m.b * m.c)) || 1;
  }
  // Half the stroke sits outside the geometry (round and square caps too).
  const e = (sw / 2) * scale;
  return new DOMRect(r.left - e, r.top - e, r.width + e * 2, r.height + e * 2);
}

function place(box, el) {
  // Mid-pan the layer is offset; re-anchor it before placing anything.
  if (overlayLayer.style.transform) updateOverlay();
  if (!el || !el.getBoundingClientRect) {
    box.style.display = "none";
    return;
  }
  const r = visualRect(el) || el.getBoundingClientRect();
  if (r.width === 0 && r.height === 0) {
    box.style.display = "none";
    return;
  }
  box.style.display = "block";
  box.style.left = r.left - 1 + "px";
  box.style.top = r.top - 1 + "px";
  box.style.width = r.width + 2 + "px";
  box.style.height = r.height + 2 + "px";
}
const ANIM_TAGS = new Set(["animate", "animateTransform", "animateMotion", "set"]);
const isAnimation = (el) => !!el && ANIM_TAGS.has(el.localName);

const multiBoxes = [];

function placeRect(box, r) {
  if (!r || (r.width === 0 && r.height === 0)) {
    box.style.display = "none";
    return;
  }
  box.style.display = "block";
  box.style.left = r.left - 1 + "px";
  box.style.top = r.top - 1 + "px";
  box.style.width = r.width + 2 + "px";
  box.style.height = r.height + 2 + "px";
}

function updateOverlay() {
  // Positions below are in window coordinates, with the layer at rest.
  overlayLayer.style.transform = "";
  overlayBase = { tx, ty, zoom };
  updateDocFrame();
  // A selected animation outlines the element it animates, without handles.
  const anim = isAnimation(selected);
  const all = selection();
  const multi = all.length > 1;
  selBox.classList.toggle("anim-target", anim);
  selBox.classList.toggle("multi", multi);
  // Several selected: an outline on each and one box around them all.
  for (let i = 0; i < Math.max(multiBoxes.length, multi ? all.length : 0); i++) {
    if (!multiBoxes[i]) {
      const b = document.createElement("div");
      b.className = "box multi-box";
      selBox.parentNode.insertBefore(b, selBox);
      multiBoxes.push(b);
    }
    if (multi && i < all.length) place(multiBoxes[i], all[i]);
    else multiBoxes[i].style.display = "none";
  }
  if (multi) {
    const rs = all.map((e) => visualRect(e)).filter((r) => r && (r.width || r.height));
    placeRect(
      selBox,
      rs.length
        ? new DOMRect(
            Math.min(...rs.map((r) => r.left)),
            Math.min(...rs.map((r) => r.top)),
            Math.max(...rs.map((r) => r.right)) - Math.min(...rs.map((r) => r.left)),
            Math.max(...rs.map((r) => r.bottom)) - Math.min(...rs.map((r) => r.top)),
          )
        : null,
    );
    hideRadiusKnobs();
    hideGradientHandles();
    return;
  }
  place(selBox, anim ? selected.parentNode : selected);
  updateRadiusKnob();
  updateGradientHandles();
  if (selected) {
    const r = selBox.getBoundingClientRect();
    selBox.classList.toggle("compact", r.width < 28 || r.height < 28);
  }
}
window.addEventListener("resize", () => {
  if (!root) return;
  if (autoFit) {
    applyZoom(fitScale(), null, null, true);
    centerContent();
  } else {
    clampPan();
    renderNow();
  }
});

// MARK: Direct manipulation

let drag = null;

function toLocal(el, x, y) {
  const m = el.getScreenCTM();
  if (!m) return { x, y };
  const p = new DOMPoint(x, y).matrixTransform(m.inverse());
  return { x: p.x, y: p.y };
}
const round = (v) => Math.round(v * 100) / 100;
const num = (s) => (s != null && /^\s*-?[\d.]+(e-?\d+)?\s*$/i.test(s) ? parseFloat(s) : null);

// Positional attributes for simple shapes, so moves edit x/y instead of adding transforms.
const positional = {
  rect: [["x", "y"]],
  image: [["x", "y"]],
  use: [["x", "y"]],
  text: [["x", "y"]],
  foreignObject: [["x", "y"]],
  circle: [["cx", "cy"]],
  ellipse: [["cx", "cy"]],
  line: [
    ["x1", "y1"],
    ["x2", "y2"],
  ],
};

function snapshotGeometry(el) {
  const pairs = positional[el.localName];
  const transform = el.getAttribute("transform");
  if (pairs && !transform) {
    const values = pairs.map(([a, b]) => [
      num(el.getAttribute(a) || "0"),
      num(el.getAttribute(b) || "0"),
    ]);
    if (values.every(([x, y]) => x != null && y != null)) return { kind: "attrs", pairs, values };
  }
  return { kind: "transform", transform };
}

function applyOffset(el, geo, dx, dy) {
  if (geo.kind === "attrs") {
    geo.pairs.forEach(([a, b], i) => {
      el.setAttribute(a, round(geo.values[i][0] + dx));
      el.setAttribute(b, round(geo.values[i][1] + dy));
    });
    return;
  }
  const t = geo.transform || "";
  const m = t.match(/^\s*translate\(\s*(-?[\d.e]+)(?:[\s,]+(-?[\d.e]+))?\s*\)\s*(.*)$/i);
  if (m) {
    const nx = round(parseFloat(m[1]) + dx),
      ny = round(parseFloat(m[2] || "0") + dy);
    el.setAttribute("transform", `translate(${nx} ${ny})${m[3] ? " " + m[3] : ""}`);
  } else {
    el.setAttribute("transform", `translate(${round(dx)} ${round(dy)})${t ? " " + t : ""}`);
  }
}

host.addEventListener("mousedown", (e) => {
  if (e.button !== 0 || !root || tool !== "select" || !editable) return;
  const t = pickTarget(e.target);
  let target = t;
  // Clicking inside an already-selected group moves the group; double-clicking drills in.
  const all = selection();
  const inGroup = all.find((s) => s.localName === "g" && t && s.contains(t));
  if (inGroup && e.detail < 2) target = inGroup;
  if (!target) {
    if (!e.shiftKey) select(null);
    beginMarquee(e);
    e.preventDefault();
    return;
  }
  if (e.shiftKey) {
    toggleSelected(target);
    e.preventDefault();
    return;
  }
  // Dragging one of several selected moves them all.
  if (!all.includes(target)) select(target);
  drag = {
    items: selection().map((el) => ({
      el,
      parent: el.parentNode,
      start: toLocal(el.parentNode, e.clientX, e.clientY),
      geo: snapshotGeometry(el),
    })),
    cx: e.clientX,
    cy: e.clientY,
    moved: false,
  };
  e.preventDefault();
});

document.addEventListener("mousedown", (e) => {
  // Clicks on the handles, the minimap or the text editor keep the selection.
  if (
    e.target === textEditor ||
    selBox.contains(e.target) ||
    docBox.contains(e.target) ||
    minimap.contains(e.target)
  )
    return;
  if (!host.contains(e.target) && e.button === 0 && editable) {
    if (!e.shiftKey) select(null);
    if (tool === "select" && !spaceDown) beginMarquee(e);
  }
});

// Right-click selects what's under the pointer (keeping a selection it's part
// of), so the app's context menu acts on it.
host.addEventListener("contextmenu", (e) => {
  if (!root || !editable) return;
  const t = pickTarget(e.target);
  if (!t) select(null);
  else if (!selection().includes(t)) select(t);
});

// MARK: Corner radius — a knob inside a selected rectangle's top-left
// corner; drag it diagonally to round the corners (rx, and ry with it).

let radiusDrag = null;

// Rectangles keep one radius (rx). Different radii per corner turn the
// rectangle into a path that remembers its box and radii in data-lines-*
// attributes, so it stays editable; equal radii turn it back into a <rect>.
const CORNER_RECT = "data-lines-rect";
const CORNER_RADII = "data-lines-corners";

function cornerInfo(el) {
  if (!el) return null;
  if (el.localName === "rect") {
    const n = (a) => parseFloat(el.getAttribute(a)) || 0;
    const w = n("width"),
      h = n("height");
    const rxAttr = el.getAttribute("rx"),
      ryAttr = el.getAttribute("ry");
    const r = Math.min(rxAttr != null ? n("rx") : ryAttr != null ? n("ry") : 0, w / 2, h / 2);
    return { x: n("x"), y: n("y"), w, h, radii: [r, r, r, r] };
  }
  if (el.localName === "path" && el.hasAttribute(CORNER_RECT)) {
    const [x, y, w, h] = el
      .getAttribute(CORNER_RECT)
      .split(/[\s,]+/)
      .map(Number);
    const radii = (el.getAttribute(CORNER_RADII) || "0 0 0 0").split(/[\s,]+/).map(Number);
    if ([x, y, w, h].some((v) => !isFinite(v))) return null;
    return { x, y, w, h, radii: [0, 1, 2, 3].map((i) => radii[i] || 0) };
  }
  return null;
}

function roundedRectPath({ x, y, w, h, radii }) {
  const m = Math.min(w, h) / 2;
  const [tl, tr, br, bl] = radii.map((r) => Math.max(0, Math.min(r, m)));
  const R = round;
  const arc = (r, ex, ey) =>
    r ? `A${R(r)} ${R(r)} 0 0 1 ${R(ex)} ${R(ey)}` : `L${R(ex)} ${R(ey)}`;
  return [
    `M${R(x + tl)} ${R(y)}`,
    `H${R(x + w - tr)}`,
    arc(tr, x + w, y + tr),
    `V${R(y + h - br)}`,
    arc(br, x + w - br, y + h),
    `H${R(x + bl)}`,
    arc(bl, x, y + h - bl),
    `V${R(y + tl)}`,
    arc(tl, x + tl, y),
    "Z",
  ].join(" ");
}

// Writes a box and radii back as a <rect> (all equal) or a corner path,
// replacing the element if its kind changes. Returns the element now in place.
function writeCorners(el, info) {
  const equal = info.radii.every((r) => Math.abs(r - info.radii[0]) < 0.01);
  const wantTag = equal ? "rect" : "path";
  let target = el;
  if (el.localName !== wantTag) {
    target = document.createElementNS(NS, wantTag);
    const skip = new Set(["x", "y", "width", "height", "rx", "ry", "d", CORNER_RECT, CORNER_RADII]);
    for (const a of Array.from(el.attributes))
      if (!skip.has(a.name)) target.setAttributeNS(a.namespaceURI, a.name, a.value);
    while (el.firstChild) target.appendChild(el.firstChild); // titles, animations
    el.parentNode.replaceChild(target, el);
    if (selected === el) selected = target;
    extras = extras.map((e) => (e === el ? target : e));
  }
  const { x, y, w, h } = info;
  if (equal) {
    target.setAttribute("x", round(x));
    target.setAttribute("y", round(y));
    target.setAttribute("width", round(w));
    target.setAttribute("height", round(h));
    const r = round(Math.min(info.radii[0], w / 2, h / 2));
    if (r > 0) target.setAttribute("rx", r);
    else target.removeAttribute("rx");
    target.removeAttribute("ry");
  } else {
    target.setAttribute(CORNER_RECT, [x, y, w, h].map(round).join(" "));
    target.setAttribute(CORNER_RADII, info.radii.map(round).join(" "));
    target.setAttribute("d", roundedRectPath(info));
  }
  return target;
}

// From the inspector: radii for the selected rectangle, corner by corner.
function setCornerRadii(tl, tr, br, bl) {
  const radii = [tl, tr, br, bl].map((v) => Math.max(0, +v || 0));
  const targets = selection().filter((el) => cornerInfo(el));
  if (!targets.length) return;
  for (const el of targets) {
    const info = cornerInfo(el);
    info.radii = radii;
    writeCorners(el, info);
  }
  updateOverlay();
  commit("Change Corner Radius", "corners");
}

function hideRadiusKnobs() {
  for (const k of radiusKnobs) k.style.display = "none";
}

function updateRadiusKnob() {
  const el = selected;
  const info = editable && el && extras.length === 0 ? cornerInfo(el) : null;
  const m = info && el.getScreenCTM && el.getScreenCTM();
  if (!info || !m || !info.w || !info.h) {
    hideRadiusKnobs();
    return;
  }
  // Inset at least 10 screen points so they can be grabbed at zero radius.
  const scale = Math.hypot(m.a, m.b) || 1;
  const { x, y, w, h, radii } = info;
  const inset = (r) => Math.min(Math.max(r, 10 / scale), w / 2, h / 2);
  const points = [
    [x + inset(radii[0]), y + inset(radii[0])],
    [x + w - inset(radii[1]), y + inset(radii[1])],
    [x + w - inset(radii[2]), y + h - inset(radii[2])],
    [x + inset(radii[3]), y + h - inset(radii[3])],
  ];
  // Very small shapes keep one knob, so the box stays usable.
  const tiny = w * scale < 60 || h * scale < 60;
  radiusKnobs.forEach((k, i) => {
    if (tiny && i > 0) {
      k.style.display = "none";
      return;
    }
    const p = new DOMPoint(points[i][0], points[i][1]).matrixTransform(m);
    k.style.display = "block";
    k.style.left = p.x + "px";
    k.style.top = p.y + "px";
  });
}

for (const knob of radiusKnobs) {
  knob.addEventListener("pointerdown", (e) => {
    if (!selected || e.button !== 0) return;
    e.preventDefault();
    e.stopPropagation();
    knob.setPointerCapture(e.pointerId);
    radiusDrag = { el: selected, id: e.pointerId, corner: +knob.dataset.corner, moved: false };
  });
  knob.addEventListener("mousedown", (e) => e.stopPropagation());
  knob.addEventListener("pointermove", (e) => {
    if (!radiusDrag || e.pointerId !== radiusDrag.id) return;
    const info = cornerInfo(radiusDrag.el);
    if (!info) return;
    const { x, y, w, h } = info;
    const p = toLocal(radiusDrag.el, e.clientX, e.clientY);
    // Along the corner's diagonal: the average of the two distances in.
    const c = radiusDrag.corner;
    const dx = c === 0 || c === 3 ? p.x - x : x + w - p.x;
    const dy = c === 0 || c === 1 ? p.y - y : y + h - p.y;
    let r = Math.max(0, Math.min((dx + dy) / 2, w / 2, h / 2));
    if (e.shiftKey) r = Math.round(r);
    // Corners move together unless Command is held.
    if (e.metaKey) info.radii[c] = r;
    else info.radii = [r, r, r, r];
    radiusDrag.moved = true;
    radiusDrag.el = writeCorners(radiusDrag.el, info);
    updateOverlay();
    reportSelection(true);
  });
  const end = (e) => {
    if (!radiusDrag || e.pointerId !== radiusDrag.id) return;
    const moved = radiusDrag.moved;
    radiusDrag = null;
    if (moved) commit("Change Corner Radius");
  };
  knob.addEventListener("pointerup", end);
  knob.addEventListener("pointercancel", end);
}

// MARK: Editing a clip path or mask on the canvas
//
// Its shapes move into a temporary group drawn over the element that uses
// it, in that element's coordinates, where they select, move and resize like
// anything else. Saving puts them back in place (see serialize), and Done or
// Esc returns them for good.

function definitionUser(def) {
  if (!def.id) return null;
  return Array.from(root.querySelectorAll("*")).find((u) =>
    refsOf(u).some(
      ([attr, target]) => target === def.id && (attr === "clip-path" || attr === "mask"),
    ),
  );
}

function editDefinitionOnCanvas(order) {
  const def = byOrder(order);
  if (!root || !editable || !def || !["clipPath", "mask"].includes(def.localName)) return;
  if (defEdit) endDefinitionEdit(false);
  const user = definitionUser(def);
  const attr = def.localName === "mask" ? "mask" : "clip-path";
  const group = document.createElementNS(NS, "g");
  group.setAttribute("data-lines-temp", "1");
  group.setAttribute("class", "lines-def-edit");
  // The shapes live in the user's coordinates (or its box, for bounding-box units).
  if (user && user.getCTM && root.getCTM) {
    let m = root.getCTM().inverse().multiply(user.getCTM());
    const units = def.getAttribute(def.localName === "mask" ? "maskContentUnits" : "clipPathUnits");
    if (units === "objectBoundingBox") {
      try {
        const b = user.getBBox();
        m = m.translate(b.x, b.y).scale(b.width, b.height);
      } catch {}
    }
    group.setAttribute(
      "transform",
      `matrix(${[m.a, m.b, m.c, m.d, m.e, m.f].map(round).join(" ")})`,
    );
  }
  root.appendChild(group);
  for (const k of Array.from(def.childNodes)) group.appendChild(k);
  const saved = user ? user.getAttribute(attr) : null;
  if (user) user.removeAttribute(attr);
  defEdit = { def, user, attr, saved, group };
  selected = Array.from(group.children)[0] || null;
  extras = [];
  updateOverlay();
  reportSelection(false);
  post({
    type: "definitionEdit",
    active: true,
    kind: def.localName,
    name: def.id || def.localName,
  });
}

// Puts the shapes back (stash) or out again (unstash), around a save.
function stashDefinitionEdit(stash) {
  const d = defEdit;
  if (stash) {
    for (const k of Array.from(d.group.childNodes)) d.def.appendChild(k);
    if (d.user && d.saved != null) d.user.setAttribute(d.attr, d.saved);
    d.group.remove();
  } else {
    root.appendChild(d.group);
    for (const k of Array.from(d.def.childNodes)) d.group.appendChild(k);
    if (d.user) d.user.removeAttribute(d.attr);
  }
}

function endDefinitionEdit(reselect) {
  const d = defEdit;
  if (!d) return;
  defEdit = null;
  for (const k of Array.from(d.group.childNodes)) d.def.appendChild(k);
  if (d.user && d.saved != null) d.user.setAttribute(d.attr, d.saved);
  d.group.remove();
  post({ type: "definitionEdit", active: false });
  scheduleOutline();
  if (reselect) select(d.user || null);
  else updateOverlay();
}

// MARK: Gradient handles — drag where a selected shape's gradient starts and
// ends (or, for a radial one, its centre and radius).

let gradientDrag = null;

function gradientOf(el) {
  if (!el || !root || !el.getAttribute) return null;
  const m = (el.getAttribute("fill") || "").match(/url\(\s*['"]?#([^'")\s]+)/);
  if (!m) return null;
  const g = root.querySelector(`[id="${m[1]}"]`);
  return g && (g.localName === "linearGradient" || g.localName === "radialGradient") ? g : null;
}

function fraction(v, fallback) {
  if (v == null || v === "") return fallback;
  return v.trim().endsWith("%") ? parseFloat(v) / 100 : parseFloat(v);
}

// The gradient's two handle points in the shape's own coordinates.
function gradientPoints(el, g) {
  const bbox = g.getAttribute("gradientUnits") !== "userSpaceOnUse";
  let b = { x: 0, y: 0, width: 1, height: 1 };
  if (bbox) {
    try {
      b = el.getBBox();
    } catch {
      return null;
    }
  }
  const P = (u, v) => (bbox ? [b.x + u * b.width, b.y + v * b.height] : [u, v]);
  if (g.localName === "linearGradient") {
    return {
      box: b,
      bbox,
      points: [
        P(fraction(g.getAttribute("x1"), 0), fraction(g.getAttribute("y1"), 0)),
        P(fraction(g.getAttribute("x2"), 1), fraction(g.getAttribute("y2"), 0)),
      ],
    };
  }
  const cx = fraction(g.getAttribute("cx"), 0.5),
    cy = fraction(g.getAttribute("cy"), 0.5),
    r = fraction(g.getAttribute("r"), 0.5);
  return { box: b, bbox, points: [P(cx, cy), P(cx + r, cy)] };
}

function hideGradientHandles() {
  gradientLine.style.display = "none";
  for (const k of gradientKnobs) k.style.display = "none";
}

function updateGradientHandles() {
  const el = selected;
  const g = editable && el && extras.length === 0 && !defEdit ? gradientOf(el) : null;
  const info = g && gradientPoints(el, g);
  const m = info && el.getScreenCTM && el.getScreenCTM();
  if (!info || !m) {
    hideGradientHandles();
    return;
  }
  const pts = info.points.map(([x, y]) => new DOMPoint(x, y).matrixTransform(m));
  const linear = g.localName === "linearGradient";
  const titles = linear
    ? [
        "Drag where the gradient starts (Shift keeps it level or diagonal)",
        "Drag where the gradient ends",
      ]
    : ["Drag the gradient's centre", "Drag to change the gradient's radius"];
  pts.forEach((p, i) => {
    const k = gradientKnobs[i];
    k.style.display = "block";
    k.style.left = p.x + "px";
    k.style.top = p.y + "px";
    k.title = titles[i];
  });
  const dx = pts[1].x - pts[0].x,
    dy = pts[1].y - pts[0].y;
  gradientLine.style.display = "block";
  gradientLine.style.left = pts[0].x + "px";
  gradientLine.style.top = pts[0].y + "px";
  gradientLine.style.width = Math.hypot(dx, dy) + "px";
  gradientLine.style.transform = `rotate(${Math.atan2(dy, dx)}rad)`;
}

for (const knob of gradientKnobs) {
  knob.addEventListener("pointerdown", (e) => {
    if (!selected || e.button !== 0) return;
    const g = gradientOf(selected);
    if (!g) return;
    e.preventDefault();
    e.stopPropagation();
    knob.setPointerCapture(e.pointerId);
    gradientDrag = { el: selected, g, index: +knob.dataset.index, id: e.pointerId, moved: false };
  });
  knob.addEventListener("mousedown", (e) => e.stopPropagation());
  knob.addEventListener("pointermove", (e) => {
    const d = gradientDrag;
    if (!d || e.pointerId !== d.id) return;
    const info = gradientPoints(d.el, d.g);
    if (!info) return;
    const p = toLocal(d.el, e.clientX, e.clientY);
    const b = info.box;
    const toUnit = (pt) =>
      info.bbox ? [(pt[0] - b.x) / (b.width || 1), (pt[1] - b.y) / (b.height || 1)] : pt;
    let [u, v] = toUnit([p.x, p.y]);
    const scale = info.bbox ? 1000 : 100;
    const fmt = (n) => String(Math.round(n * scale) / scale);
    if (e.shiftKey && d.g.localName === "linearGradient") {
      // Shift keeps the line level, upright or diagonal.
      const [ou, ov] = toUnit(info.points[1 - d.index]);
      const a = Math.round(Math.atan2(v - ov, u - ou) / (Math.PI / 4)) * (Math.PI / 4);
      const len = Math.hypot(u - ou, v - ov);
      u = ou + Math.cos(a) * len;
      v = ov + Math.sin(a) * len;
    }
    if (d.g.localName === "linearGradient") {
      d.g.setAttribute(d.index === 0 ? "x1" : "x2", fmt(u));
      d.g.setAttribute(d.index === 0 ? "y1" : "y2", fmt(v));
    } else if (d.index === 0) {
      d.g.setAttribute("cx", fmt(u));
      d.g.setAttribute("cy", fmt(v));
      d.g.removeAttribute("fx");
      d.g.removeAttribute("fy");
    } else {
      const cx = fraction(d.g.getAttribute("cx"), 0.5),
        cy = fraction(d.g.getAttribute("cy"), 0.5);
      d.g.setAttribute("r", fmt(Math.max(0.001, Math.hypot(u - cx, v - cy))));
    }
    d.moved = true;
    updateGradientHandles();
  });
  const end = (e) => {
    if (!gradientDrag || e.pointerId !== gradientDrag.id) return;
    const moved = gradientDrag.moved;
    gradientDrag = null;
    if (moved) commit("Move Gradient");
  };
  knob.addEventListener("pointerup", end);
  knob.addEventListener("pointercancel", end);
}

// MARK: Marquee — drag on empty canvas to select everything it touches.

let marquee = null;
const marqueeBox = document.createElement("div");
marqueeBox.id = "marquee";
document.body.appendChild(marqueeBox);

function beginMarquee(e) {
  marquee = { x: e.clientX, y: e.clientY, keep: e.shiftKey ? selection() : [], moved: false };
}

function marqueeRect(e) {
  const x = Math.min(marquee.x, e.clientX),
    y = Math.min(marquee.y, e.clientY);
  return new DOMRect(x, y, Math.abs(e.clientX - marquee.x), Math.abs(e.clientY - marquee.y));
}

// What a marquee picks from: the drawing's top level, looking through
// wrapper groups that hold everything.
function marqueeScope() {
  let scope = root;
  for (;;) {
    const visual = Array.from(scope.children).filter((c) => !nonVisual.has(c.localName));
    if (visual.length === 1 && visual[0].localName === "g") scope = visual[0];
    else return visual;
  }
}

function updateMarquee(e) {
  if (!marquee.moved && Math.hypot(e.clientX - marquee.x, e.clientY - marquee.y) < 3) return;
  marquee.moved = true;
  const r = marqueeRect(e);
  placeRect(marqueeBox, r);
  const hits = marqueeScope().filter((el) => {
    if (isHidden(el) || ANIM_TAGS.has(el.localName)) return false;
    const b = visualRect(el) || el.getBoundingClientRect();
    if (!b.width && !b.height) return false;
    return b.left < r.right && b.right > r.left && b.top < r.bottom && b.bottom > r.top;
  });
  const merged = [...marquee.keep, ...hits.filter((h) => !marquee.keep.includes(h))];
  selected = merged[0] || null;
  extras = merged.slice(1);
  updateOverlay();
}

function endMarquee() {
  marqueeBox.style.display = "none";
  if (marquee.moved) reportSelection(false);
  marquee = null;
}

window.addEventListener("mousemove", (e) => {
  if (marquee) {
    updateMarquee(e);
    return;
  }
  if (!drag) {
    if (!editable) return;
    const t = pickTarget(e.target);
    if (t && t !== selected) place(hoverBox, t);
    else hoverBox.style.display = "none";
    return;
  }
  if (!drag.moved && Math.hypot(e.clientX - drag.cx, e.clientY - drag.cy) < 3) return;
  drag.moved = true;
  hoverBox.style.display = "none";
  // Lock the axis from the primary element's movement, then move each in
  // its own parent's coordinates.
  const first = drag.items[0];
  const p0 = toLocal(first.parent, e.clientX, e.clientY);
  const lockX = e.shiftKey && Math.abs(p0.x - first.start.x) <= Math.abs(p0.y - first.start.y);
  const lockY = e.shiftKey && !lockX;
  for (const item of drag.items) {
    const p = toLocal(item.parent, e.clientX, e.clientY);
    applyOffset(item.el, item.geo, lockX ? 0 : p.x - item.start.x, lockY ? 0 : p.y - item.start.y);
  }
  updateOverlay();
});

window.addEventListener("mouseup", () => {
  if (marquee) endMarquee();
  if (drag && drag.moved) commit("Move");
  drag = null;
});

document.addEventListener("mouseleave", () => {
  hoverBox.style.display = "none";
});

document.addEventListener("keydown", (e) => {
  if (!root || !editable) return;
  if (!e.metaKey && !e.ctrlKey && !e.altKey && TOOL_KEYS[e.key.toLowerCase()]) {
    setTool(TOOL_KEYS[e.key.toLowerCase()], true);
    e.preventDefault();
    return;
  }
  if (e.key === "Escape" && tool !== "select") {
    setTool("select", true);
    e.preventDefault();
    return;
  }
  if (e.key === "Escape" && defEdit) {
    endDefinitionEdit(true);
    e.preventDefault();
    return;
  }
  if (e.key === "Escape") {
    if (selected) selectParent();
    else select(null);
    e.preventDefault();
    return;
  }
  if (!selected) return;
  if ((e.key === "Backspace" || e.key === "Delete") && !e.metaKey) {
    deleteSelected();
    e.preventDefault();
    return;
  }
  const step = e.shiftKey ? 10 : 1;
  const d = {
    ArrowLeft: [-step, 0],
    ArrowRight: [step, 0],
    ArrowUp: [0, -step],
    ArrowDown: [0, step],
  }[e.key];
  if (d && !e.metaKey) {
    for (const el of selection()) applyOffset(el, snapshotGeometry(el), d[0], d[1]);
    updateOverlay();
    commit("Nudge", "nudge");
    e.preventDefault();
  }
});

// MARK: Editing commands

function setAttrNS(el, name, value) {
  const existing = el.getAttributeNode(name);
  if (existing && existing.namespaceURI) el.setAttributeNS(existing.namespaceURI, name, value);
  else if (name.startsWith("xlink:")) el.setAttributeNS(XLINK, name, value);
  else el.setAttribute(name, value);
}

function setAttr(name, value, coalesce) {
  const el = selected || root;
  if (!el || !name) return;
  try {
    setAttrNS(el, name, value);
    for (const other of extras) if (root.contains(other)) setAttrNS(other, name, value);
  } catch {
    return;
  }
  if (el === root) updateIntrinsicSize();
  updateOverlay();
  commit(`Change ${label(name)}`, coalesce ? `attr:${name}` : null);
}

// Sets a paint and its opacity together (fill + fill-opacity), as one undo step.
function setPaint(name, color, opacity, coalesce) {
  if (!root) return;
  const all = selection().length ? selection() : [root];
  for (const el of all) paintOne(el, name, color, opacity);
  updateOverlay();
  commit(`Change ${label(name)}`, coalesce ? `paint:${name}` : null);
}

function paintOne(el, name, color, opacity) {
  el.setAttribute(name, color);
  // An inline style wins over the attribute; drop it so the change shows.
  if (el.style) {
    el.style.removeProperty(name);
    el.style.removeProperty(name + "-opacity");
    if (!el.getAttribute("style")) el.removeAttribute("style");
  }
  // A new stroke gets a width that shows at the drawing's scale.
  if (name === "stroke" && color !== "none" && !el.hasAttribute("stroke-width") && el.getBBox) {
    try {
      const b = el.getBBox();
      el.setAttribute("stroke-width", round(Math.max(1, Math.hypot(b.width, b.height) / 80)));
    } catch {}
  }
  const opacityAttr = name + "-opacity";
  if (opacity == null || opacity >= 0.999) el.removeAttribute(opacityAttr);
  else el.setAttribute(opacityAttr, Math.round(opacity * 100) / 100);
}

function removeAttr(name) {
  const el = selected || root;
  if (!el || !el.hasAttribute(name)) return;
  el.removeAttribute(name);
  if (el === root) updateIntrinsicSize();
  updateOverlay();
  commit(`Remove ${label(name)}`);
}

function setText(text) {
  if (!selected) return;
  selected.textContent = text;
  updateOverlay();
  commit("Change Text", "text");
}

// "stroke-width" → "Stroke Width", for undo names. Tolerates odd names like "data-".
function label(name) {
  return (
    name
      .replace(/^xlink:/, "")
      .split("-")
      .filter((s) => s)
      .map((s) => s[0].toUpperCase() + s.slice(1))
      .join(" ") || "Attribute"
  );
}

// Insert with indentation that matches the surrounding markup.
function indentFor(parent) {
  const first = Array.from(parent.childNodes).find((n) => n.nodeType === 3 && /\n/.test(n.data));
  if (first) return first.data.slice(first.data.lastIndexOf("\n"));
  let depth = 0,
    p = parent;
  while (p && p !== root) {
    depth++;
    p = p.parentNode;
  }
  return "\n" + "  ".repeat(depth + 1);
}

function insert(el, parent, before) {
  const indent = indentFor(parent);
  if (before) {
    parent.insertBefore(el, before);
    parent.insertBefore(document.createTextNode(indent), before);
    return;
  }
  const last = parent.lastChild;
  if (last && last.nodeType === 3 && /^\s*$/.test(last.data)) {
    parent.insertBefore(document.createTextNode(indent), last);
    parent.insertBefore(el, last);
  } else {
    parent.appendChild(document.createTextNode(indent));
    parent.appendChild(el);
    parent.appendChild(document.createTextNode("\n"));
  }
}

function removeWithWhitespace(el) {
  const prev = el.previousSibling;
  if (prev && prev.nodeType === 3 && /^\s*$/.test(prev.data)) prev.remove();
  el.remove();
}

function viewCenter() {
  const vb = root.viewBox && root.viewBox.baseVal;
  if (vb && vb.width > 0)
    return { x: vb.x + vb.width / 2, y: vb.y + vb.height / 2, s: Math.min(vb.width, vb.height) };
  const { w, h } = intrinsicSize();
  return { x: w / 2, y: h / 2, s: Math.min(w, h) };
}

const palette = ["#0a84ff", "#30d158", "#ff9f0a", "#ff375f", "#bf5af2", "#64d2ff"];
let paletteIndex = 0;

function addShape(kind) {
  if (!root) return;
  const { x, y, s } = viewCenter();
  const u = s / 512; // scale defaults to the drawing
  const r = (v) => round(v);
  const fill = palette[paletteIndex++ % palette.length];
  const make = (tag, attrs) => {
    const el = document.createElementNS(NS, tag);
    for (const [k, v] of Object.entries(attrs)) el.setAttribute(k, v);
    return el;
  };
  let el;
  switch (kind) {
    case "rect":
      el = make("rect", {
        x: r(x - 80 * u),
        y: r(y - 56 * u),
        width: r(160 * u),
        height: r(112 * u),
        fill,
      });
      break;
    case "roundedRect":
      el = make("rect", {
        x: r(x - 80 * u),
        y: r(y - 56 * u),
        width: r(160 * u),
        height: r(112 * u),
        rx: r(24 * u),
        fill,
      });
      break;
    case "triangle":
      el = make("polygon", {
        points: [
          [x, y - 64 * u],
          [x + 72 * u, y + 56 * u],
          [x - 72 * u, y + 56 * u],
        ]
          .map((p) => p.map(r).join(","))
          .join(" "),
        fill,
        "stroke-linejoin": "round",
      });
      break;
    case "hexagon": {
      const pts = [];
      for (let i = 0; i < 6; i++) {
        const a = Math.PI / 6 + (i * Math.PI) / 3;
        pts.push(`${r(x + 68 * u * Math.cos(a))},${r(y + 68 * u * Math.sin(a))}`);
      }
      el = make("polygon", { points: pts.join(" "), fill });
      break;
    }
    case "arrow":
      el = make("path", {
        d: `M${r(x - 80 * u)} ${r(y + 48 * u)} L${r(x + 64 * u)} ${r(y - 38 * u)} M${r(x + 22 * u)} ${r(y - 46 * u)} L${r(x + 64 * u)} ${r(y - 38 * u)} L${r(x + 50 * u)} ${r(y + 3 * u)}`,
        fill: "none",
        stroke: fill,
        "stroke-width": r(8 * u),
        "stroke-linecap": "round",
        "stroke-linejoin": "round",
      });
      break;
    case "group":
      el = make("g", {});
      break;
    case "circle":
      el = make("circle", { cx: r(x), cy: r(y), r: r(64 * u), fill });
      break;
    case "ellipse":
      el = make("ellipse", { cx: r(x), cy: r(y), rx: r(96 * u), ry: r(56 * u), fill });
      break;
    case "line":
      el = make("line", {
        x1: r(x - 80 * u),
        y1: r(y + 48 * u),
        x2: r(x + 80 * u),
        y2: r(y - 48 * u),
        stroke: fill,
        "stroke-width": r(8 * u),
        "stroke-linecap": "round",
      });
      break;
    case "star": {
      const pts = [];
      for (let i = 0; i < 10; i++) {
        const a = -Math.PI / 2 + (i * Math.PI) / 5,
          rad = (i % 2 ? 30 : 72) * u;
        pts.push(`${r(x + rad * Math.cos(a))},${r(y + rad * Math.sin(a))}`);
      }
      el = make("polygon", { points: pts.join(" "), fill, "stroke-linejoin": "round" });
      break;
    }
    case "text":
      el = make("text", {
        x: r(x),
        y: r(y),
        "font-family": "-apple-system, Helvetica, sans-serif",
        "font-size": r(40 * u),
        "text-anchor": "middle",
        "dominant-baseline": "middle",
        fill,
      });
      el.textContent = "Text";
      break;
    default:
      return;
  }
  const parent = selected && selected.localName === "g" ? selected : root;
  insert(el, parent);
  select(el);
  const names = { rect: "Rectangle", roundedRect: "Rounded Rectangle", group: "Group" };
  commit(`Add ${names[kind] || kind[0].toUpperCase() + kind.slice(1)}`);
}

// Embeds an image (as a data URL), fitted inside the drawing.
function addImage(dataURL, width, height) {
  if (!root) return;
  const { x, y, s: size } = viewCenter();
  const scale = Math.min(1, (size * 0.8) / Math.max(width, height));
  const w = Math.round(width * scale * 100) / 100,
    h = Math.round(height * scale * 100) / 100;
  const el = document.createElementNS(NS, "image");
  el.setAttribute("x", Math.round((x - w / 2) * 100) / 100);
  el.setAttribute("y", Math.round((y - h / 2) * 100) / 100);
  el.setAttribute("width", w);
  el.setAttribute("height", h);
  el.setAttribute("href", dataURL);
  insert(el, selected && selected.localName === "g" ? selected : root);
  select(el);
  commit("Add Image");
}

function deleteSelected() {
  const all = selection();
  if (!all.length) return;
  const parent = selected.parentNode;
  for (const el of all) if (root.contains(el)) removeWithWhitespace(el);
  select(all.length === 1 && parent !== root && root.contains(parent) ? parent : null);
  commit("Delete");
}

function duplicateSelected() {
  const all = selection();
  if (!all.length) return;
  const copies = all.map((el) => {
    const copy = el.cloneNode(true);
    if (copy.id) copy.removeAttribute("id");
    insert(copy, el.parentNode, el.nextSibling);
    applyOffset(copy, snapshotGeometry(copy), 10, 10);
    return copy;
  });
  selectMany(copies);
  commit("Duplicate");
}

// Restacks the selection; several move together, keeping their order (the
// one nearest the destination goes first).
function reorder(mode) {
  if (!selected) return;
  const all = selection();
  if (all.length === 1) return reorderOne(selected, mode);
  const inDocument = Array.from(root.querySelectorAll("*")).filter((e) => all.includes(e));
  const ordered = mode === "front" || mode === "forward" ? inDocument.reverse() : inDocument;
  const keep = all;
  inBatch(() => {
    for (const el of mode === "front" || mode === "back" ? ordered.reverse() : ordered)
      reorderOne(el, mode);
  });
  selectMany(keep);
}

function reorderOne(el, mode) {
  const parent = el.parentNode;
  const siblings = Array.from(parent.children);
  const i = siblings.indexOf(el);
  let ref;
  switch (mode) {
    case "forward":
      if (i === siblings.length - 1) return;
      ref = siblings[i + 1].nextSibling;
      break;
    case "backward":
      if (i === 0) return;
      ref = siblings[i - 1];
      break;
    case "front":
      if (i === siblings.length - 1) return;
      ref = null;
      break;
    case "back":
      if (i === 0) return;
      ref = siblings[0];
      break;
  }
  removeWithWhitespace(el);
  if (ref === null) insert(el, parent);
  else insert(el, parent, ref);
  updateOverlay();
  const names = {
    front: "Bring to Front",
    forward: "Bring Forward",
    backward: "Send Backward",
    back: "Send to Back",
  };
  commit(names[mode]);
}

function groupSelected() {
  if (!selected) return;
  const all = selection();
  if (all.length > 1) {
    // Group siblings of the primary in document order; others stay put.
    const parent = selected.parentNode;
    const members = Array.from(parent.children).filter((c) => all.includes(c));
    const g = document.createElementNS(NS, "g");
    insert(g, parent, members[members.length - 1].nextSibling);
    for (const m of members) {
      removeWithWhitespace(m);
      insert(m, g);
    }
    select(g);
    commit("Group");
    return;
  }
  const g = document.createElementNS(NS, "g");
  const parent = selected.parentNode,
    next = selected.nextSibling;
  removeWithWhitespace(selected);
  const el = selected;
  insert(g, parent, next);
  insert(el, g);
  select(g);
  commit("Group");
}

// Mirrors each selected element across its own centre.
function flipSelected(axis) {
  const all = selection();
  if (!all.length) return;
  for (const el of all) {
    let b;
    try {
      b = el.getBBox();
    } catch {
      continue;
    }
    const cx = round(b.x + b.width / 2),
      cy = round(b.y + b.height / 2);
    const s = axis === "h" ? "-1 1" : "1 -1";
    const f = `translate(${cx} ${cy}) scale(${s}) translate(${-cx} ${-cy})`;
    const t = el.getAttribute("transform");
    el.setAttribute("transform", t ? `${t} ${f}` : f);
  }
  updateOverlay();
  commit(axis === "h" ? "Flip Horizontal" : "Flip Vertical");
}

function ungroupSelected() {
  if (!selected || selected.localName !== "g") return;
  const g = selected,
    parent = g.parentNode;
  const transform = g.getAttribute("transform");
  const kids = Array.from(g.children);
  for (const k of kids) {
    removeWithWhitespace(k);
    if (transform)
      k.setAttribute(
        "transform",
        transform + (k.getAttribute("transform") ? " " + k.getAttribute("transform") : ""),
      );
    insert(k, parent, g);
  }
  removeWithWhitespace(g);
  select(kids[0] || null);
  commit("Ungroup");
}

function copySelected() {
  const all = selection();
  return all.length
    ? all
        .map((el) =>
          new XMLSerializer()
            .serializeToString(el)
            .replace(/ xmlns="http:\/\/www\.w3\.org\/2000\/svg"/, ""),
        )
        .join("\n")
    : null;
}

function pasteMarkup(text) {
  if (!root) return;
  text = text
    .trim()
    .replace(/^<\?xml[^>]*\?>\s*/, "")
    .replace(/^<!DOCTYPE[^>]*>\s*/i, "");
  const isSVG = /^<svg[\s>]/.test(text);
  const wrapped = isSVG ? text : `<svg xmlns="${NS}" xmlns:xlink="${XLINK}">${text}</svg>`;
  const doc = new DOMParser().parseFromString(wrapped, "image/svg+xml");
  if (doc.querySelector("parsererror")) {
    post({ type: "error", message: "The clipboard doesn't contain valid SVG." });
    return;
  }
  let nodes = Array.from(doc.documentElement.children);
  if (isSVG) {
    const g = document.createElementNS(NS, "g");
    nodes.forEach((n) => g.appendChild(document.importNode(n, true)));
    nodes = [g];
  } else {
    nodes = nodes.map((n) => document.importNode(n, true));
  }
  if (!nodes.length) return;
  const parent = selected ? selected.parentNode : root;
  const before = selected ? selected.nextSibling : null;
  for (const n of nodes) {
    insert(n, parent, before);
    applyOffset(n, snapshotGeometry(n), 10, 10);
  }
  select(nodes[nodes.length - 1]);
  commit("Paste");
}

// MARK: Zoom and export

// MARK: Camera — zoom changes the drawing's layout size; panning moves it.

const PAD = 32;
let tx = 0,
  ty = 0; // the drawing's top-left corner, in viewport points
let frame = 0;

function contentSize() {
  const { w, h } = intrinsicSize();
  return { W: w * zoom, H: h * zoom };
}

// Pan freely at any zoom, but keep at least KEEP points of the drawing on screen.
const KEEP = 48;
function clampPan() {
  if (!root) return;
  const { W, H } = contentSize(),
    vw = window.innerWidth,
    vh = window.innerHeight;
  tx = Math.min(vw - Math.min(KEEP, W), Math.max(Math.min(KEEP, W) - W, tx));
  ty = Math.min(vh - Math.min(KEEP, H), Math.max(Math.min(KEEP, H) - H, ty));
}

// Panning by hand ends Zoom to Fit, so resizing the window won't snap the drawing back.
function leaveFit() {
  if (!autoFit) return;
  autoFit = false;
  post({ type: "zoom", value: zoom, fit: false });
}

// The selection, handles and document frame live on one layer. A pan
// moves that layer with the drawing by the same transform, in the same
// frame, so they stay together (repositioning each box separately lagged a
// frame behind the composited drawing). Anything else re-places them.
let overlayBase = null;
let panOnly = false;

function render() {
  frame = 0;
  host.style.transform = `translate3d(${tx}px, ${ty}px, 0)`;
  if (panOnly && overlayBase && overlayBase.zoom === zoom) {
    overlayLayer.style.transform = `translate3d(${tx - overlayBase.tx}px, ${ty - overlayBase.ty}px, 0)`;
  } else {
    updateOverlay();
  }
  panOnly = false;
  updateMinimap();
}
// A render where only the pan changed.
function schedulePan() {
  if (!frame) panOnly = true;
  if (!frame) frame = requestAnimationFrame(render);
}
function renderNow() {
  if (frame) cancelAnimationFrame(frame);
  render();
}

// The part of the window not covered by floating panels, set by the app.
let insets = { left: 0, right: 0, top: 0, bottom: 0 };
function visibleArea() {
  const w = Math.max(1, window.innerWidth - insets.left - insets.right);
  const h = Math.max(1, window.innerHeight - insets.top - insets.bottom);
  return { x: insets.left, y: insets.top, w, h };
}
let minimapShift = 0;
function setMinimapShift(px) {
  minimapShift = px || 0;
  minimap.style.left = insets.left + 12 + minimapShift + "px";
}
function setInsets(left, right, top, bottom) {
  insets = { left, right, top, bottom };
  minimap.style.left = left + 12 + minimapShift + "px";
  minimap.style.bottom = bottom + 12 + "px";
  if (!root) return;
  if (autoFit) {
    applyZoom(fitScale(), null, null, true);
    centerContent();
  } else {
    renderNow();
  }
}

function fitScale() {
  if (!root || window.innerWidth < 2 || window.innerHeight < 2) return zoom;
  const { w, h } = intrinsicSize();
  const area = visibleArea();
  const fit = Math.min((area.w - PAD * 2) / w, (area.h - PAD * 2) / h);
  return Math.max(MIN_ZOOM, Math.min(fit, 8));
}

// Changes the display scale, keeping the drawing point under (ax, ay) — in
// viewport points — fixed on screen. Defaults to the window center.
function applyZoom(z, ax, ay, fitting) {
  z = Math.max(MIN_ZOOM, Math.min(MAX_ZOOM, z));
  if (!root) {
    zoom = z;
    return;
  }
  if (ax == null) {
    const area = visibleArea();
    ax = area.x + area.w / 2;
    ay = area.y + area.h / 2;
  }
  const px = (ax - tx) / zoom,
    py = (ay - ty) / zoom;
  zoom = z;
  updateIntrinsicSize();
  tx = ax - px * z;
  ty = ay - py * z;
  clampPan();
  renderNow();
  post({ type: "zoom", value: zoom, fit: !!fitting || autoFit });
}

function setZoom(z, ax, ay) {
  autoFit = false;
  applyZoom(z, ax, ay);
}
function zoomBy(factor, ax, ay) {
  setZoom(zoom * factor, ax, ay);
}
function zoomToFit() {
  autoFit = true;
  applyZoom(fitScale(), null, null, true);
  centerContent();
}

function centerContent() {
  const { W, H } = contentSize();
  const area = visibleArea();
  tx = area.x + (area.w - W) / 2;
  ty = area.y + (area.h - H) / 2;
  clampPan();
  renderNow();
}

function panBy(dx, dy) {
  leaveFit();
  tx -= dx;
  ty -= dy;
  clampPan();
  hoverBox.style.display = "none";
  schedulePan();
}

// Trackpad scrolling pans (mouse wheels are turned into zoom on the native side).
window.addEventListener(
  "wheel",
  (e) => {
    e.preventDefault();
    const scale = e.deltaMode === 1 ? 16 : e.deltaMode === 2 ? window.innerHeight : 1;
    panBy(e.deltaX * scale, e.deltaY * scale);
  },
  { passive: false },
);

// MARK: Panning — middle-button drag, or Space-drag like other design apps.

let pan = null,
  spaceDown = false;

document.addEventListener(
  "pointerdown",
  (e) => {
    if (!(e.button === 1 || (e.button === 0 && (spaceDown || tool === "hand")))) return;
    // preventDefault on pointerdown also suppresses the compatibility mouse
    // events, so selection and dragging don't react to a pan.
    e.preventDefault();
    e.stopImmediatePropagation();
    pan = { id: e.pointerId, x: e.clientX, y: e.clientY, tx, ty };
    document.documentElement.setPointerCapture(e.pointerId);
    document.body.classList.add("panning");
    hoverBox.style.display = "none";
  },
  true,
);

document.addEventListener(
  "pointermove",
  (e) => {
    if (!pan || e.pointerId !== pan.id) return;
    e.stopImmediatePropagation();
    // Position from the drag origin (not accumulated deltas), applied once per frame.
    leaveFit();
    tx = pan.tx + (e.clientX - pan.x);
    ty = pan.ty + (e.clientY - pan.y);
    clampPan();
    schedulePan();
  },
  true,
);

function endPan(e) {
  if (!pan || e.pointerId !== pan.id) return;
  pan = null;
  document.body.classList.remove("panning");
}
document.addEventListener("pointerup", endPan, true);
document.addEventListener("pointercancel", endPan, true);

// Middle-click shouldn't trigger autoscroll or paste.
document.addEventListener("auxclick", (e) => {
  if (e.button === 1) e.preventDefault();
});

document.addEventListener(
  "keydown",
  (e) => {
    if (e.code === "Space" && !e.repeat && e.target !== textEditor) {
      spaceDown = true;
      document.body.classList.add("space");
      e.preventDefault();
    }
  },
  true,
);
document.addEventListener(
  "keyup",
  (e) => {
    if (e.code === "Space") {
      spaceDown = false;
      document.body.classList.remove("space");
    }
  },
  true,
);
window.addEventListener("blur", () => {
  spaceDown = false;
  document.body.classList.remove("space");
});

// MARK: Minimap — appears when the drawing doesn't fit, showing the visible region.

const minimap = document.getElementById("minimap");
const miniImg = document.getElementById("mini-img");
const miniView = document.getElementById("mini-view");
const MINI_W = 168,
  MINI_H = 120;
let thumbTimer = 0,
  miniDrag = null;

function miniScale() {
  const { w, h } = intrinsicSize();
  return Math.min(MINI_W / w, MINI_H / h);
}

function scheduleThumbnail() {
  clearTimeout(thumbTimer);
  thumbTimer = setTimeout(() => {
    if (!root) return;
    const { w, h } = intrinsicSize();
    const clone = root.cloneNode(true);
    clone.setAttribute("width", w);
    clone.setAttribute("height", h);
    miniImg.src =
      "data:image/svg+xml;charset=utf-8," +
      encodeURIComponent(new XMLSerializer().serializeToString(clone));
    updateMinimap();
  }, 120);
}

function updateMinimap() {
  if (!root) {
    minimap.classList.remove("shown");
    return;
  }
  const { w, h } = intrinsicSize();
  const { W, H } = contentSize(),
    vw = window.innerWidth,
    vh = window.innerHeight;
  // Shown whenever part of the drawing is out of view.
  const overflowing = tx < -0.5 || ty < -0.5 || tx + W > vw + 0.5 || ty + H > vh + 0.5;
  minimap.classList.toggle("shown", overflowing || !!miniDrag);
  if (!overflowing) return;
  document.getElementById("mini-zoom").textContent = Math.round(zoom * 100) + "%";
  const s = miniScale();
  miniImg.style.width = w * s + "px";
  miniImg.style.height = h * s + "px";
  // The visible region, in drawing units, clipped to the drawing.
  const x0 = Math.max(0, -tx / zoom),
    y0 = Math.max(0, -ty / zoom);
  const x1 = Math.min(w, (vw - tx) / zoom),
    y1 = Math.min(h, (vh - ty) / zoom);
  miniView.style.left = x0 * s + "px";
  miniView.style.top = y0 * s + "px";
  miniView.style.width = Math.max(4, (x1 - x0) * s) + "px";
  miniView.style.height = Math.max(4, (y1 - y0) * s) + "px";
}

// Click or drag in the minimap to move the visible region there.
function miniMoveTo(e) {
  const r = miniImg.getBoundingClientRect(),
    s = miniScale();
  const cx = (e.clientX - r.left) / s,
    cy = (e.clientY - r.top) / s;
  leaveFit();
  tx = window.innerWidth / 2 - cx * zoom;
  ty = window.innerHeight / 2 - cy * zoom;
  clampPan();
  schedulePan();
}
minimap.addEventListener("pointerdown", (e) => {
  if (e.button !== 0) return;
  e.preventDefault();
  e.stopPropagation();
  miniDrag = e.pointerId;
  minimap.setPointerCapture(e.pointerId);
  miniMoveTo(e);
});
minimap.addEventListener("pointermove", (e) => {
  if (miniDrag === e.pointerId) miniMoveTo(e);
});
minimap.addEventListener("pointerup", () => {
  miniDrag = null;
  updateMinimap();
});
minimap.addEventListener("mousedown", (e) => e.stopPropagation());

// MARK: Transform — resize and rotate handles, and exact bounds.

const HANDLES = {
  nw: [-1, -1],
  n: [0, -1],
  ne: [1, -1],
  e: [1, 0],
  se: [1, 1],
  s: [0, 1],
  sw: [-1, 1],
  w: [-1, 0],
};
const GEOMETRY = {
  rect: ["x", "y", "width", "height", "rx", "ry"],
  image: ["x", "y", "width", "height"],
  use: ["x", "y", "width", "height"],
  foreignObject: ["x", "y", "width", "height"],
  circle: ["cx", "cy", "r"],
  ellipse: ["cx", "cy", "rx", "ry"],
  line: ["x1", "y1", "x2", "y2"],
  polygon: ["points"],
  polyline: ["points"],
  text: ["x", "y", "font-size"],
};
let xf = null;

// The attributes that hold an element's geometry; corner paths keep their box.
function geometryKeys(el) {
  if (el.localName === "path" && el.hasAttribute(CORNER_RECT))
    return ["d", CORNER_RECT, CORNER_RADII];
  return GEOMETRY[el.localName];
}

function snapshotShape(el) {
  const attrs = {};
  for (const a of geometryKeys(el) || []) attrs[a] = el.getAttribute(a);
  return { attrs, transform: el.getAttribute("transform") };
}
function restoreShape(el, snap) {
  for (const [a, v] of Object.entries(snap.attrs)) {
    if (v == null) el.removeAttribute(a);
    else el.setAttribute(a, v);
  }
  if (snap.transform == null) el.removeAttribute("transform");
  else el.setAttribute("transform", snap.transform);
}
// Attribute edits are only exact when the element isn't rotated or skewed.
function editsAttributes(el, snap) {
  if (!geometryKeys(el)) return false;
  const t = snap.transform || "";
  return !t.trim() || /^\s*translate\([^)]*\)\s*$/i.test(t);
}
// Replaces a transform chain with one matrix, so repeated edits stay tidy.
function consolidate(el) {
  const list = el.transform && el.transform.baseVal;
  if (!list || list.numberOfItems < 2) return;
  const m = list.consolidate().matrix;
  const r = (v) => Math.round(v * 10000) / 10000;
  el.setAttribute(
    "transform",
    `matrix(${r(m.a)} ${r(m.b)} ${r(m.c)} ${r(m.d)} ${r(m.e)} ${r(m.f)})`,
  );
}

// Scales `el` by (sx, sy) around a point given in screen coordinates.
function scaleAround(el, snap, sx, sy, ax, ay) {
  restoreShape(el, snap);
  if (editsAttributes(el, snap)) {
    const a = toLocal(el, ax, ay);
    const mx = (v) => round(a.x + (parseFloat(v || 0) - a.x) * sx);
    const my = (v) => round(a.y + (parseFloat(v || 0) - a.y) * sy);
    const g = snap.attrs;
    if (el.localName === "path") {
      // A rectangle with its own corner radii: scale the box, keep it a rectangle.
      const info = cornerInfo(el);
      if (info) {
        let x = mx(info.x),
          y = my(info.y);
        let w = info.w * sx,
          h = info.h * sy;
        if (w < 0) {
          x += w;
          w = -w;
        }
        if (h < 0) {
          y += h;
          h = -h;
        }
        const k = Math.min(Math.abs(sx), Math.abs(sy));
        writeCorners(el, { x, y, w, h, radii: info.radii.map((r) => r * k) });
      }
      return;
    }
    switch (el.localName) {
      case "rect":
      case "image":
      case "use":
      case "foreignObject": {
        let x = mx(g.x),
          y = my(g.y);
        let w = round(parseFloat(g.width || 0) * sx),
          h = round(parseFloat(g.height || 0) * sy);
        if (w < 0) {
          x = round(x + w);
          w = -w;
        }
        if (h < 0) {
          y = round(y + h);
          h = -h;
        }
        el.setAttribute("x", x);
        el.setAttribute("y", y);
        el.setAttribute("width", w);
        el.setAttribute("height", h);
        if (g.rx != null) el.setAttribute("rx", round(parseFloat(g.rx) * Math.abs(sx)));
        if (g.ry != null) el.setAttribute("ry", round(parseFloat(g.ry) * Math.abs(sy)));
        return;
      }
      case "circle": {
        const k =
          Math.abs(sx) === 1
            ? Math.abs(sy)
            : Math.abs(sy) === 1
              ? Math.abs(sx)
              : Math.max(Math.abs(sx), Math.abs(sy));
        el.setAttribute("cx", mx(g.cx));
        el.setAttribute("cy", my(g.cy));
        el.setAttribute("r", round(parseFloat(g.r || 0) * k));
        return;
      }
      case "ellipse":
        el.setAttribute("cx", mx(g.cx));
        el.setAttribute("cy", my(g.cy));
        el.setAttribute("rx", round(parseFloat(g.rx || 0) * Math.abs(sx)));
        el.setAttribute("ry", round(parseFloat(g.ry || 0) * Math.abs(sy)));
        return;
      case "line":
        el.setAttribute("x1", mx(g.x1));
        el.setAttribute("y1", my(g.y1));
        el.setAttribute("x2", mx(g.x2));
        el.setAttribute("y2", my(g.y2));
        return;
      case "polygon":
      case "polyline": {
        const n = (g.points || "")
          .trim()
          .split(/[\s,]+/)
          .map(parseFloat);
        const out = [];
        for (let i = 0; i + 1 < n.length; i += 2) out.push(`${mx(n[i])},${my(n[i + 1])}`);
        el.setAttribute("points", out.join(" "));
        return;
      }
      case "text":
        if (g.x != null || sx !== 1) el.setAttribute("x", mx(g.x));
        if (g.y != null || sy !== 1) el.setAttribute("y", my(g.y));
        el.setAttribute(
          "font-size",
          round(parseFloat(g["font-size"] || 16) * Math.abs(sy !== 1 ? sy : sx)),
        );
        return;
    }
  }
  // Anything else (paths, groups, rotated shapes) scales with a transform.
  const p = toLocal(el.parentNode, ax, ay);
  const prior = snap.transform ? " " + snap.transform : "";
  el.setAttribute(
    "transform",
    `translate(${p.x} ${p.y}) scale(${sx} ${sy}) translate(${-p.x} ${-p.y})${prior}`,
  );
  consolidate(el);
}

function rotateAround(el, snap, degrees, cx, cy) {
  restoreShape(el, snap);
  const p = toLocal(el.parentNode, cx, cy);
  const prior = snap.transform ? " " + snap.transform : "";
  el.setAttribute("transform", `rotate(${round(degrees)} ${round(p.x)} ${round(p.y)})${prior}`);
  consolidate(el);
}

selBox.addEventListener("pointerdown", (e) => {
  const handle = e.target.dataset && e.target.dataset.handle;
  if (!handle || !selected || e.button !== 0) return;
  e.preventDefault();
  e.stopPropagation();
  selBox.setPointerCapture(e.pointerId);
  const r = selected.getBoundingClientRect();
  xf = {
    el: selected,
    handle,
    rect: r,
    x0: e.clientX,
    y0: e.clientY,
    id: e.pointerId,
    snap: snapshotShape(selected),
    moved: false,
  };
  if (handle === "rot") {
    xf.cx = r.left + r.width / 2;
    xf.cy = r.top + r.height / 2;
    xf.a0 = Math.atan2(e.clientY - xf.cy, e.clientX - xf.cx);
    selBox.classList.add("rotating");
  }
});

selBox.addEventListener("pointermove", (e) => {
  if (!xf || e.pointerId !== xf.id) return;
  xf.moved = true;
  if (xf.handle === "rot") {
    let deg = ((Math.atan2(e.clientY - xf.cy, e.clientX - xf.cx) - xf.a0) * 180) / Math.PI;
    if (e.shiftKey) deg = Math.round(deg / 15) * 15;
    rotateAround(xf.el, xf.snap, deg, xf.cx, xf.cy);
    // Keep the box where it started while rotating; it re-fits on release.
    return;
  }
  const [hx, hy] = HANDLES[xf.handle];
  const r = xf.rect;
  const fromCenter = e.altKey;
  const k = fromCenter ? 2 : 1;
  let sx = hx ? (r.width + hx * k * (e.clientX - xf.x0)) / r.width : 1;
  let sy = hy ? (r.height + hy * k * (e.clientY - xf.y0)) / r.height : 1;
  if (e.shiftKey) {
    // Keep proportions: corners follow the larger change, edges scale both ways.
    const s = hx && hy ? (Math.abs(sx) > Math.abs(sy) ? sx : sy) : hx ? sx : sy;
    sx = Math.sign(sx || 1) * Math.abs(s);
    sy = Math.sign(sy || 1) * Math.abs(s);
  }
  const clamp = (v) => (Math.abs(v) < 0.01 ? 0.01 * Math.sign(v || 1) : v);
  const ax = fromCenter
    ? r.left + r.width / 2
    : hx === 1
      ? r.left
      : hx === -1
        ? r.right
        : r.left + r.width / 2;
  const ay = fromCenter
    ? r.top + r.height / 2
    : hy === 1
      ? r.top
      : hy === -1
        ? r.bottom
        : r.top + r.height / 2;
  scaleAround(xf.el, xf.snap, clamp(sx), clamp(sy), ax, ay);
  updateOverlay();
});

function endTransform(e) {
  if (!xf || e.pointerId !== xf.id) return;
  const { moved, handle } = xf;
  xf = null;
  selBox.classList.remove("rotating");
  updateOverlay();
  if (moved) commit(handle === "rot" ? "Rotate" : "Resize");
}
selBox.addEventListener("pointerup", endTransform);
selBox.addEventListener("pointercancel", endTransform);

// The element's box in its parent's coordinates (what the inspector shows).
function boundsOf(el) {
  if (!el.getBBox) return null;
  // A hidden element has no box; measure it as if shown, so the inspector
  // keeps its real position and size.
  const hidden = el.getAttribute("display") === "none";
  const style = el.getAttribute("style");
  if (hidden) el.style.display = "inline";
  let b;
  try {
    b = el.getBBox();
  } catch {
    b = null;
  }
  if (hidden) {
    if (style == null) el.removeAttribute("style");
    else el.setAttribute("style", style);
  }
  if (!b) return null;
  const parent = el.parentNode;
  const m = el.getCTM && parent.getCTM ? parent.getCTM().inverse().multiply(el.getCTM()) : null;
  const pts = [
    [b.x, b.y],
    [b.x + b.width, b.y],
    [b.x, b.y + b.height],
    [b.x + b.width, b.y + b.height],
  ].map(([x, y]) => (m ? new DOMPoint(x, y).matrixTransform(m) : { x, y }));
  const xs = pts.map((p) => p.x),
    ys = pts.map((p) => p.y);
  const x = Math.min(...xs),
    y = Math.min(...ys);
  return [round(x), round(y), round(Math.max(...xs) - x), round(Math.max(...ys) - y)];
}

function rotationOf(el) {
  const list = el.transform && el.transform.baseVal;
  if (!list || !list.numberOfItems) return 0;
  const m = list.consolidate().matrix;
  return round((Math.atan2(m.b, m.a) * 180) / Math.PI);
}

// Exact position and size from the inspector, in parent coordinates.
function setBounds(x, y, w, h) {
  if (!selected) return;
  const b = boundsOf(selected);
  if (!b) return;
  const [bx, by, bw, bh] = b;
  const snap = snapshotShape(selected);
  if ((w != null && bw && w !== bw) || (h != null && bh && h !== bh)) {
    const m = selected.parentNode.getScreenCTM();
    const anchor = new DOMPoint(bx, by).matrixTransform(m);
    scaleAround(
      selected,
      snap,
      w != null && bw ? w / bw : 1,
      h != null && bh ? h / bh : 1,
      anchor.x,
      anchor.y,
    );
  }
  const after = boundsOf(selected);
  const dx = x != null ? x - after[0] : 0,
    dy = y != null ? y - after[1] : 0;
  if (dx || dy) applyOffset(selected, snapshotGeometry(selected), dx, dy);
  updateOverlay();
  commit(w != null || h != null ? "Change Size" : "Move", "bounds");
}

// Sets the primary selection's rotation; others turn by the same amount,
// each around its own centre.
function setRotation(degrees) {
  if (!selected) return;
  const delta = degrees - rotationOf(selected);
  for (const el of selection()) {
    const r = el.getBoundingClientRect();
    rotateAround(el, snapshotShape(el), delta, r.left + r.width / 2, r.top + r.height / 2);
  }
  updateOverlay();
  commit("Rotate", "rotation");
}

// Sets the viewBox to the bounds of everything drawn, trimming empty space.
// The drawing's box over the whole of its animations: sampled across their
// running time and combined, so fitting never clips something mid-animation.
function animatedBBox() {
  const anims = Array.from(root.querySelectorAll("animate, animateTransform, animateMotion, set"));
  const box = () => {
    try {
      const b = root.getBBox();
      return b.width || b.height ? { x: b.x, y: b.y, r: b.x + b.width, b: b.y + b.height } : null;
    } catch {
      return null;
    }
  };
  let u = box();
  if (!anims.length) return u;
  let end = 0;
  for (const a of anims) {
    let start = 0,
      dur = 0;
    try {
      start = a.getStartTime();
    } catch {}
    try {
      dur = a.getSimpleDuration();
    } catch {}
    end = Math.max(end, start + (isFinite(dur) ? dur : 0));
  }
  end = Math.min(end, 60);
  if (!end) return u;
  const wasPaused = root.animationsPaused();
  const now = root.getCurrentTime();
  root.pauseAnimations();
  const steps = 48;
  for (let i = 0; i <= steps; i++) {
    root.setCurrentTime((end * i) / steps);
    const b = box();
    if (!b) continue;
    u = u
      ? {
          x: Math.min(u.x, b.x),
          y: Math.min(u.y, b.y),
          r: Math.max(u.r, b.r),
          b: Math.max(u.b, b.b),
        }
      : b;
  }
  root.setCurrentTime(now);
  if (!wasPaused) root.unpauseAnimations();
  return u;
}

function fitViewBoxToContent() {
  if (!root) return;
  const u = animatedBBox();
  if (!u) return;
  const b = { x: u.x, y: u.y, width: u.r - u.x, height: u.b - u.y };
  if (!b.width || !b.height) return;
  root.setAttribute("viewBox", [b.x, b.y, b.width, b.height].map(round).join(" "));
  if (root.hasAttribute("width") && root.hasAttribute("height")) {
    const ratio = b.width / b.height,
      w = parseFloat(root.getAttribute("width"));
    if (w) root.setAttribute("height", round(w / ratio));
  }
  updateIntrinsicSize();
  if (autoFit) {
    applyZoom(fitScale(), null, null, true);
    centerContent();
  }
  commit("Fit to Content");
}

// MARK: Tools — draw shapes by dragging, place text by clicking.

let tool = "select";
const TOOL_KEYS = {
  v: "select",
  h: "hand",
  r: "rect",
  o: "ellipse",
  l: "line",
  p: "star",
  t: "text",
};
const SHAPE_TOOLS = new Set([
  "rect",
  "roundedRect",
  "ellipse",
  "line",
  "arrow",
  "triangle",
  "hexagon",
  "star",
]);
let drawingShape = null;

// `fromCanvas` tells the app when the change started here (a key or a finished drawing).
function setTool(name, fromCanvas) {
  tool = name;
  document.body.dataset.tool = name;
  if (name !== "select") hoverBox.style.display = "none";
  if (fromCanvas) post({ type: "tool", tool: name });
}

// Points of a polygon tool inside the unit square.
function unitPolygon(kind) {
  if (kind === "triangle")
    return [
      [0.5, 0],
      [1, 1],
      [0, 1],
    ];
  if (kind === "hexagon")
    return [...Array(6)].map((_, i) => {
      const a = Math.PI / 6 + (i * Math.PI) / 3;
      return [0.5 + 0.5 * Math.cos(a), 0.5 + 0.5 * Math.sin(a)];
    });
  return [...Array(10)].map((_, i) => {
    const a = -Math.PI / 2 + (i * Math.PI) / 5,
      r = i % 2 ? 0.2 : 0.5;
    return [0.5 + r * Math.cos(a), 0.5 + r * Math.sin(a)];
  });
}

function shapeGeometry(kind, x0, y0, x1, y1) {
  const x = Math.min(x0, x1),
    y = Math.min(y0, y1),
    w = Math.abs(x1 - x0),
    h = Math.abs(y1 - y0);
  switch (kind) {
    case "rect":
      return { x: round(x), y: round(y), width: round(w), height: round(h) };
    case "roundedRect":
      return {
        x: round(x),
        y: round(y),
        width: round(w),
        height: round(h),
        rx: round(Math.min(w, h) * 0.18),
      };
    case "ellipse":
      return { cx: round(x + w / 2), cy: round(y + h / 2), rx: round(w / 2), ry: round(h / 2) };
    case "line":
      return { x1: round(x0), y1: round(y0), x2: round(x1), y2: round(y1) };
    case "arrow": {
      const a = Math.atan2(y1 - y0, x1 - x0),
        len = Math.max(8, Math.hypot(x1 - x0, y1 - y0) * 0.18);
      const hx = (d) => round(x1 - len * Math.cos(a + d)),
        hy = (d) => round(y1 - len * Math.sin(a + d));
      return {
        d: `M${round(x0)} ${round(y0)} L${round(x1)} ${round(y1)} M${hx(0.5)} ${hy(0.5)} L${round(x1)} ${round(y1)} L${hx(-0.5)} ${hy(-0.5)}`,
      };
    }
    default:
      return {
        points: unitPolygon(kind)
          .map(([u, v]) => `${round(x + u * w)},${round(y + v * h)}`)
          .join(" "),
      };
  }
}

function newShape(kind) {
  const tag =
    { rect: "rect", roundedRect: "rect", ellipse: "ellipse", line: "line", arrow: "path" }[kind] ||
    "polygon";
  const el = document.createElementNS(NS, tag);
  const colour = palette[paletteIndex++ % palette.length];
  if (kind === "line" || kind === "arrow") {
    el.setAttribute("fill", "none");
    el.setAttribute("stroke", colour);
    el.setAttribute("stroke-width", round(Math.max(2, intrinsicSize().w / 128)));
    el.setAttribute("stroke-linecap", "round");
    el.setAttribute("stroke-linejoin", "round");
  } else {
    el.setAttribute("fill", colour);
  }
  return el;
}

function applyGeometry(el, geo) {
  for (const [k, v] of Object.entries(geo)) el.setAttribute(k, v);
}

document.addEventListener(
  "pointerdown",
  (e) => {
    if (e.button !== 0 || !root || spaceDown) return;
    if (!(SHAPE_TOOLS.has(tool) || tool === "text")) return;
    if (minimap.contains(e.target) || selBox.contains(e.target) || e.target === textEditor) return;
    e.preventDefault();
    e.stopImmediatePropagation();
    const parent = selected && selected.localName === "g" ? selected : root;
    const p = toLocal(parent, e.clientX, e.clientY);
    if (tool === "text") {
      const el = document.createElementNS(NS, "text");
      el.setAttribute("x", round(p.x));
      el.setAttribute("y", round(p.y));
      el.setAttribute("font-family", "-apple-system, Helvetica, sans-serif");
      el.setAttribute("font-size", round(Math.max(12, intrinsicSize().h / 12)));
      el.setAttribute("fill", "#1c1c1e");
      el.textContent = "Text";
      insert(el, parent);
      select(el);
      commit("Add Text");
      setTool("select", true);
      beginTextEdit(el);
      return;
    }
    const el = newShape(tool);
    insert(el, parent);
    drawingShape = {
      el,
      parent,
      kind: tool,
      x0: p.x,
      y0: p.y,
      cx: e.clientX,
      cy: e.clientY,
      id: e.pointerId,
    };
    applyGeometry(el, shapeGeometry(tool, p.x, p.y, p.x, p.y));
    document.documentElement.setPointerCapture(e.pointerId);
  },
  true,
);

document.addEventListener(
  "pointermove",
  (e) => {
    if (!drawingShape || e.pointerId !== drawingShape.id) return;
    e.stopImmediatePropagation();
    const d = drawingShape;
    let p = toLocal(d.parent, e.clientX, e.clientY);
    let dx = p.x - d.x0,
      dy = p.y - d.y0;
    if (e.shiftKey) {
      if (d.kind === "line" || d.kind === "arrow") {
        // Snap the angle to 45° steps.
        const len = Math.hypot(dx, dy),
          a = Math.round(Math.atan2(dy, dx) / (Math.PI / 4)) * (Math.PI / 4);
        dx = len * Math.cos(a);
        dy = len * Math.sin(a);
      } else {
        const m = Math.max(Math.abs(dx), Math.abs(dy));
        dx = m * Math.sign(dx || 1);
        dy = m * Math.sign(dy || 1);
      }
    }
    let x0 = d.x0,
      y0 = d.y0;
    if (e.altKey && d.kind !== "line" && d.kind !== "arrow") {
      x0 -= dx;
      y0 -= dy;
    }
    applyGeometry(d.el, shapeGeometry(d.kind, x0, y0, d.x0 + dx, d.y0 + dy));
    updateOverlay();
  },
  true,
);

document.addEventListener(
  "pointerup",
  (e) => {
    if (!drawingShape || e.pointerId !== drawingShape.id) return;
    e.stopImmediatePropagation();
    const d = drawingShape;
    drawingShape = null;
    // A click without a drag places a default-size shape centred on the click.
    if (Math.hypot(e.clientX - d.cx, e.clientY - d.cy) < 4) {
      const s = Math.min(intrinsicSize().w, intrinsicSize().h) / 4;
      const geo =
        d.kind === "line" || d.kind === "arrow"
          ? shapeGeometry(d.kind, d.x0 - s / 2, d.y0 + s / 4, d.x0 + s / 2, d.y0 - s / 4)
          : shapeGeometry(d.kind, d.x0 - s / 2, d.y0 - s / 2, d.x0 + s / 2, d.y0 + s / 2);
      applyGeometry(d.el, geo);
    }
    select(d.el);
    const names = {
      rect: "Rectangle",
      roundedRect: "Rounded Rectangle",
      ellipse: "Ellipse",
      line: "Line",
      arrow: "Arrow",
      triangle: "Triangle",
      hexagon: "Hexagon",
      star: "Star",
    };
    commit(`Add ${names[d.kind]}`);
    setTool("select", true);
  },
  true,
);

// Adds a reusable definition (gradient, clip path, mask or filter) to <defs>,
// ready to connect to shapes in the graph.
// With `applyOrder`, the new definition is sized to that element and applied
// to it (fill, clip-path, mask or filter), which stays selected.
function addDefinition(kind, applyOrder) {
  if (!root) return;
  const target = applyOrder != null ? byOrder(applyOrder) : null;
  let defs = Array.from(root.children).find((c) => c.localName === "defs");
  if (!defs) {
    defs = document.createElementNS(NS, "defs");
    insert(defs, root, root.firstElementChild);
  }
  const { w, h } = intrinsicSize();
  const vb = root.viewBox && root.viewBox.baseVal;
  let box = vb && vb.width ? { x: vb.x, y: vb.y, w: vb.width, h: vb.height } : { x: 0, y: 0, w, h };
  if (target && target.getBBox) {
    try {
      const b = target.getBBox();
      if (b.width || b.height) box = { x: b.x, y: b.y, w: b.width || 1, h: b.height || 1 };
    } catch {}
  }
  const make = (tag, attrs, children) => {
    const el = document.createElementNS(NS, tag);
    for (const [k, v] of Object.entries(attrs || {})) el.setAttribute(k, v);
    for (const c of children || []) insert(c, el);
    return el;
  };
  const a = palette[paletteIndex++ % palette.length],
    b = palette[paletteIndex++ % palette.length];
  const stops = () => [
    make("stop", { offset: "0", "stop-color": a }),
    make("stop", { offset: "1", "stop-color": b }),
  ];
  const specs = {
    linearGradient: ["linearGradient", "gradient", { x1: "0", y1: "0", x2: "1", y2: "1" }, stops],
    radialGradient: ["radialGradient", "radial", { cx: "0.5", cy: "0.5", r: "0.5" }, stops],
    pattern: [
      "pattern",
      "pattern",
      (() => {
        const size = round(Math.max(4, Math.min(box.w, box.h) / 10));
        return { width: size, height: size, patternUnits: "userSpaceOnUse" };
      })(),
      () => {
        const size = round(Math.max(4, Math.min(box.w, box.h) / 10));
        return [
          make("rect", { width: size, height: size, fill: a }),
          make("circle", { cx: size / 2, cy: size / 2, r: round(size / 4), fill: b }),
        ];
      },
    ],
    clipPath: [
      "clipPath",
      "clip",
      {},
      () => [
        make("circle", {
          cx: round(box.x + box.w / 2),
          cy: round(box.y + box.h / 2),
          r: round(Math.min(box.w, box.h) / 2.5),
        }),
      ],
    ],
    mask: [
      "mask",
      "mask",
      {},
      () => [
        make("rect", {
          x: round(box.x),
          y: round(box.y),
          width: round(box.w),
          height: round(box.h),
          fill: "white",
        }),
        make("circle", {
          cx: round(box.x + box.w / 2),
          cy: round(box.y + box.h / 2),
          r: round(Math.min(box.w, box.h) / 5),
          fill: "black",
        }),
      ],
    ],
    blur: [
      "filter",
      "blur",
      {},
      () => [make("feGaussianBlur", { stdDeviation: round(Math.max(1, box.w / 128)) })],
    ],
    shadow: [
      "filter",
      "shadow",
      { x: "-20%", y: "-20%", width: "140%", height: "140%" },
      () => [
        make("feDropShadow", {
          dx: "0",
          dy: round(box.h / 96),
          stdDeviation: round(box.w / 96),
          "flood-opacity": "0.35",
        }),
      ],
    ],
  };
  const spec = specs[kind];
  if (!spec) return;
  const [tag, base, attrs, children] = spec;
  const el = make(tag, { id: uniqueID(base), ...attrs }, children());
  insert(el, defs);
  if (target && target !== root) {
    const attr =
      {
        linearGradient: "fill",
        radialGradient: "fill",
        pattern: "fill",
        clipPath: "clip-path",
        mask: "mask",
      }[kind] || "filter";
    target.setAttribute(attr, `url(#${el.id})`);
    select(target);
  } else select(el);
  const names = {
    linearGradient: "Linear Gradient",
    radialGradient: "Radial Gradient",
    clipPath: "Clip Path",
    mask: "Mask",
    blur: "Blur",
    pattern: "Pattern",
    shadow: "Drop Shadow",
  };
  commit(`Add ${names[kind]}`);
}

// Adds a stop to a gradient, halfway between the last two, in the last colour.
function addStop(order) {
  const grad = byOrder(order);
  if (!grad) return;
  const stops = Array.from(grad.children).filter((c) => c.localName === "stop");
  const off = (s) => {
    const v = (s && s.getAttribute("offset")) || "0";
    return v.endsWith("%") ? parseFloat(v) / 100 : parseFloat(v) || 0;
  };
  const last = stops[stops.length - 1];
  const prev = stops[stops.length - 2];
  const stop = document.createElementNS(NS, "stop");
  const at = last ? (prev ? (off(prev) + off(last)) / 2 : off(last) / 2) : 0;
  stop.setAttribute("offset", round(at));
  const colour = last
    ? last.getAttribute("stop-color") || (last.style && last.style.stopColor) || "#000000"
    : palette[paletteIndex++ % palette.length];
  stop.setAttribute("stop-color", colour);
  insert(stop, grad, last || null);
  commit("Add Stop");
}

// Adds a shape to a mask or clip path, centred on what its other shapes
// cover (or the drawing). Kinds are the drawing tools' shapes, "text", or
// "selection" for a copy of the selected element. Masks get white, which
// shows what's under it.
function addDefinitionShape(order, kind) {
  const def = byOrder(order);
  if (!def || !root) return;
  let b = null;
  try {
    const bb = def.getBBox && def.getBBox();
    if (bb && (bb.width || bb.height)) b = bb;
  } catch {}
  if (!b) {
    const vb = root.viewBox && root.viewBox.baseVal;
    const { w, h } = intrinsicSize();
    b = vb && vb.width ? vb : { x: 0, y: 0, width: w, height: h };
  }
  const isMask = def.localName === "mask";
  let el;
  if (kind === "selection") {
    if (!selected || selected === def || def.contains(selected)) return;
    el = selected.cloneNode(true);
    el.removeAttribute("id");
    for (const a of ["clip-path", "mask", "filter"]) el.removeAttribute(a);
  } else if (kind === "text") {
    el = document.createElementNS(NS, "text");
    el.setAttribute("x", round(b.x + b.width / 2));
    el.setAttribute("y", round(b.y + b.height / 2));
    el.setAttribute("text-anchor", "middle");
    el.setAttribute("dominant-baseline", "middle");
    el.setAttribute("font-family", "-apple-system, Helvetica, sans-serif");
    el.setAttribute("font-weight", "800");
    el.setAttribute("font-size", round(Math.min(b.width, b.height) / 3));
    el.textContent = "Text";
  } else {
    const x0 = b.x + b.width / 4,
      y0 = b.y + b.height / 4,
      x1 = b.x + (b.width * 3) / 4,
      y1 = b.y + (b.height * 3) / 4;
    if (kind === "circle") {
      el = document.createElementNS(NS, "circle");
      el.setAttribute("cx", round(b.x + b.width / 2));
      el.setAttribute("cy", round(b.y + b.height / 2));
      el.setAttribute("r", round(Math.min(b.width, b.height) / 3));
    } else {
      const tag =
        { rect: "rect", roundedRect: "rect", ellipse: "ellipse", line: "line", arrow: "path" }[
          kind
        ] || "polygon";
      el = document.createElementNS(NS, tag);
      for (const [k, v] of Object.entries(shapeGeometry(kind, x0, y0, x1, y1)))
        el.setAttribute(k, v);
    }
  }
  if (isMask) {
    el.setAttribute("fill", "white");
    el.removeAttribute("stroke");
  }
  insert(el, def);
  commit(isMask ? "Add Shape to Mask" : "Add Shape to Clip Path");
}

// Deletes definitions nothing refers to: not by url(#id) or href anywhere in
// the drawing, nor by #id in its style sheets. Repeats, since removing one
// (a gradient another inherited from) can leave others unused.
function removeUnusedDefinitions() {
  if (!root) return;
  let removed = 0;
  for (let pass = 0; pass < 5; pass++) {
    const used = new Set();
    for (const el of root.querySelectorAll("*")) for (const [, id] of refsOf(el)) used.add(id);
    // Style sheets and inline style attributes can point at ids too.
    const css = Array.from(root.querySelectorAll("style"))
      .map((s) => s.textContent)
      .concat(Array.from(root.querySelectorAll("[style]")).map((e) => e.getAttribute("style")))
      .join("\n");
    const unused = Array.from(root.querySelectorAll("*")).filter(
      (el) =>
        DEFINITION_TAGS.has(el.localName) &&
        (!el.id || (!used.has(el.id) && !css.includes("#" + el.id))),
    );
    if (!unused.length) break;
    for (const el of unused) removeWithWhitespace(el);
    removed += unused.length;
  }
  if (!removed) return;
  select(null);
  commit(removed === 1 ? "Remove Unused Definition" : `Remove ${removed} Unused Definitions`);
}

// Swaps white and black in a mask, so what it showed it hides.
function invertMask(order) {
  const mask = byOrder(order);
  if (!mask) return;
  const white = /^(white|#fff|#ffffff)$/i,
    black = /^(black|#000|#000000)$/i;
  for (const el of mask.querySelectorAll("*")) {
    const f = el.getAttribute("fill");
    if (f && white.test(f)) el.setAttribute("fill", "black");
    else if (f && black.test(f)) el.setAttribute("fill", "white");
    else if (!f && el.localName !== "g") el.setAttribute("fill", "white");
  }
  commit("Invert Mask");
}

// Removes every reference this element makes (fill, clip-path, mask, …).
function removeAllReferences(order) {
  const el = byOrder(order);
  if (!el) return;
  const refs = refsOf(el);
  if (!refs.length) return;
  for (const [attr] of refs) {
    if (attr === "href") {
      el.removeAttribute("href");
      el.removeAttributeNS(XLINK, "href");
    } else el.removeAttribute(attr);
  }
  commit("Remove References");
}

// MARK: Document frame — the drawing's extents, with handles to resize it.
// Resizing changes the canvas, not the artwork: width/height grow and the
// viewBox grows with them, so everything keeps its size and place.

const docBox = document.getElementById("doc");
const docSize = document.getElementById("doc-size");
let docFrameShown = false;
let docDrag = null;

function showDocumentFrame(on) {
  docFrameShown = !!on;
  updateDocFrame();
}

function updateDocFrame() {
  // Mid-pan the layer is offset; place everything afresh instead.
  if (overlayLayer.style.transform) {
    updateOverlay();
    return;
  }
  if (!docFrameShown || !root || !editable) {
    docBox.style.display = "none";
    return;
  }
  const r = host.getBoundingClientRect();
  docBox.style.display = "block";
  docBox.style.left = r.left + "px";
  docBox.style.top = r.top + "px";
  docBox.style.width = r.width + "px";
  docBox.style.height = r.height + "px";
  const { w, h } = intrinsicSize();
  docSize.textContent = `${round(w)} × ${round(h)}`;
}

function numericAttr(name) {
  const v = root.getAttribute(name);
  return v != null && /^\s*[\d.]+\s*(px)?\s*$/.test(v) ? parseFloat(v) : null;
}

docBox.addEventListener("pointerdown", (e) => {
  const handle = e.target.dataset && e.target.dataset.doc;
  if (!handle || e.button !== 0 || !root) return;
  e.preventDefault();
  e.stopPropagation();
  docBox.setPointerCapture(e.pointerId);
  const vb = root.viewBox && root.viewBox.baseVal;
  const { w, h } = intrinsicSize();
  docDrag = {
    handle,
    id: e.pointerId,
    x0: e.clientX,
    y0: e.clientY,
    w0: w,
    h0: h,
    tx0: tx,
    ty0: ty,
    vb0: vb && vb.width ? [vb.x, vb.y, vb.width, vb.height] : null,
    width0: root.getAttribute("width"),
    height0: root.getAttribute("height"),
    hasW: numericAttr("width") != null,
    hasH: numericAttr("height") != null,
    moved: false,
  };
});

docBox.addEventListener("pointermove", (e) => {
  const d = docDrag;
  if (!d || e.pointerId !== d.id) return;
  d.moved = true;
  const [hx, hy] = HANDLES[d.handle];
  let w = Math.max(1, d.w0 + (hx * (e.clientX - d.x0)) / zoom);
  let h = Math.max(1, d.h0 + (hy * (e.clientY - d.y0)) / zoom);
  if (e.shiftKey && hx && hy) {
    const k = Math.max(w / d.w0, h / d.h0);
    w = d.w0 * k;
    h = d.h0 * k;
  }
  w = Math.round(w);
  h = Math.round(h);
  // Growing from the left or top moves the origin, so the artwork stays put.
  const offX = hx < 0 ? d.w0 - w : 0,
    offY = hy < 0 ? d.h0 - h : 0;
  if (d.vb0) {
    const ux = d.vb0[2] / d.w0,
      uy = d.vb0[3] / d.h0;
    root.setAttribute(
      "viewBox",
      [d.vb0[0] + offX * ux, d.vb0[1] + offY * uy, w * ux, h * uy].map(round).join(" "),
    );
  }
  if (d.hasW || !d.vb0) root.setAttribute("width", w);
  if (d.hasH || !d.vb0) root.setAttribute("height", h);
  updateIntrinsicSize();
  tx = d.tx0 + offX * zoom;
  ty = d.ty0 + offY * zoom;
  renderNow();
});

function endDocDrag(e) {
  const d = docDrag;
  if (!d || e.pointerId !== d.id) return;
  docDrag = null;
  if (d.moved) {
    leaveFit();
    commit("Resize Canvas");
  }
}
docBox.addEventListener("pointerup", endDocDrag);
docBox.addEventListener("pointercancel", endDocDrag);

// MARK: Animation — SMIL animations, played and scrubbed from the timeline.

// Drawings open still, at the start; Play (on the canvas or timeline) starts them.
let animPaused = true;
let animTime = 0;
let timeTimer = 0;
let timelineActive = false;

// Where playback loops back to the start while the timeline shows (0: never).
let loopEnd = 0;

function setTimelineLoop(seconds) {
  loopEnd = seconds > 0 ? seconds : 0;
}

function wrapLoop() {
  if (!root || animPaused || !timelineActive || !loopEnd) return;
  if (root.getCurrentTime() >= loopEnd) {
    root.setCurrentTime(0);
    animTime = 0;
    syncCSSAnimations(0);
  }
}

function reportTime() {
  if (!root) return;
  wrapLoop();
  post({ type: "time", t: root.getCurrentTime(), playing: !animPaused });
}

function updateTimeReports() {
  const want = timelineActive && !animPaused;
  if (want && !timeTimer) {
    timeTimer = setInterval(() => {
      reportTime();
      updateOverlay();
    }, 50);
  } else if (!want && timeTimer) {
    clearInterval(timeTimer);
    timeTimer = 0;
  }
}

// The timeline is open; report the playhead while it plays.
function setTimelineActive(on) {
  timelineActive = !!on;
  updateTimeReports();
  reportTime();
}

// Playback speed. SMIL has no rate, so off 1× the drawing stays paused and
// the playhead is stepped by hand each frame.
let animSpeed = 1;
let speedFrame = 0;
let speedLast = 0;

function speedTick(now) {
  if (!root || animPaused || animSpeed === 1) {
    speedFrame = 0;
    return;
  }
  const dt = speedLast ? (now - speedLast) / 1000 : 0;
  speedLast = now;
  animTime = root.getCurrentTime() + dt * animSpeed;
  root.setCurrentTime(animTime);
  wrapLoop();
  speedFrame = requestAnimationFrame(speedTick);
}

function applySpeed() {
  if (!root) return;
  if (animPaused) return;
  if (animSpeed === 1) {
    if (speedFrame) cancelAnimationFrame(speedFrame);
    speedFrame = 0;
    root.unpauseAnimations();
  } else {
    root.pauseAnimations();
    speedLast = 0;
    if (!speedFrame) speedFrame = requestAnimationFrame(speedTick);
  }
}

function animSetSpeed(s) {
  animSpeed = s > 0 ? s : 1;
  applySpeed();
  syncCSSAnimations(null);
}

function animPlay() {
  if (!root) return;
  animPaused = false;
  applySpeed();
  syncCSSAnimations(null);
  updateTimeReports();
  reportTime();
}

// Pauses at the start.
function animStop() {
  animPause();
  animSeek(0);
}

function animPause() {
  if (!root) return;
  root.pauseAnimations();
  animPaused = true;
  animTime = root.getCurrentTime();
  syncCSSAnimations(animTime);
  updateTimeReports();
  reportTime();
}

function animSeek(t) {
  if (!root) return;
  root.setCurrentTime(Math.max(0, t));
  animTime = Math.max(0, t);
  syncCSSAnimations(animTime);
  updateOverlay();
  reportTime();
}

// A re-rendered drawing starts its timeline at zero; keep a paused playhead.
function restoreAnimationState() {
  if (animPaused) {
    root.pauseAnimations();
    root.setCurrentTime(animTime);
    syncCSSAnimations(animTime);
  } else if (animSpeed !== 1) {
    root.setCurrentTime(animTime);
    applySpeed();
    syncCSSAnimations(animTime);
  }
}

// Adds an animation preset to an element, as a SMIL child it controls.
function addAnimation(order, preset) {
  const el = byOrder(order);
  if (!el || el === root) return;
  let b;
  try {
    b = el.getBBox();
  } catch {
    b = { x: 0, y: 0, width: 0, height: 0 };
  }
  const cx = round(b.x + b.width / 2),
    cy = round(b.y + b.height / 2);
  const fill = el.getAttribute("fill") || "#000000";
  const other = palette[paletteIndex++ % palette.length];
  const make = (tag, attrs) => {
    const a = document.createElementNS(NS, tag);
    for (const [k, v] of Object.entries(attrs)) a.setAttribute(k, v);
    return a;
  };
  let anim;
  switch (preset) {
    case "fade":
      anim = make("animate", {
        attributeName: "opacity",
        values: "1;0.15;1",
        dur: "2s",
        repeatCount: "indefinite",
      });
      break;
    case "fadeIn":
      anim = make("animate", {
        attributeName: "opacity",
        from: "0",
        to: "1",
        dur: "1s",
        fill: "freeze",
      });
      break;
    case "spin":
      anim = make("animateTransform", {
        attributeName: "transform",
        type: "rotate",
        from: `0 ${cx} ${cy}`,
        to: `360 ${cx} ${cy}`,
        dur: "3s",
        repeatCount: "indefinite",
        additive: "sum",
      });
      break;
    case "slide": {
      const d = round(Math.max(10, b.width / 3));
      anim = make("animateTransform", {
        attributeName: "transform",
        type: "translate",
        values: `0 0; ${d} 0; 0 0`,
        dur: "2s",
        repeatCount: "indefinite",
        additive: "sum",
      });
      break;
    }
    case "colour":
      anim = make("animate", {
        attributeName: "fill",
        values: `${fill};${other};${fill}`,
        dur: "3s",
        repeatCount: "indefinite",
      });
      break;
    case "draw": {
      const len = el.getTotalLength ? round(el.getTotalLength()) : 0;
      if (!len) return;
      el.setAttribute("stroke-dasharray", len);
      if (!el.getAttribute("stroke") || el.getAttribute("stroke") === "none")
        el.setAttribute("stroke", fill === "none" ? "#000000" : fill);
      anim = make("animate", {
        attributeName: "stroke-dashoffset",
        from: len,
        to: "0",
        dur: "2s",
        fill: "freeze",
      });
      break;
    }
    default:
      return;
  }
  insert(anim, el);
  select(anim);
  commit("Add Animation");
}

// MARK: Inline text editing — double-click a text element to type in place.

const textEditor = document.getElementById("text-editor");
let editingText = null;

function beginTextEdit(el) {
  const r = el.getBoundingClientRect();
  editingText = el;
  textEditor.value = el.textContent;
  const size = parseFloat(getComputedStyle(el).fontSize) || 16;
  textEditor.style.display = "block";
  textEditor.style.left = r.left - 4 + "px";
  textEditor.style.top = r.top - 3 + "px";
  textEditor.style.minWidth = Math.max(60, r.width + 8) + "px";
  textEditor.style.width = Math.max(60, r.width + 24) + "px";
  textEditor.style.height = r.height + 6 + "px";
  textEditor.style.fontSize = size * zoom + "px";
  textEditor.focus();
  textEditor.select();
}

function endTextEdit(save) {
  if (!editingText) return;
  const el = editingText;
  editingText = null;
  textEditor.style.display = "none";
  if (save && textEditor.value !== el.textContent) {
    el.textContent = textEditor.value;
    updateOverlay();
    commit("Edit Text");
  }
}

textEditor.addEventListener("keydown", (e) => {
  e.stopPropagation();
  if (e.key === "Enter") {
    e.preventDefault();
    endTextEdit(true);
  }
  if (e.key === "Escape") {
    e.preventDefault();
    endTextEdit(false);
  }
});
textEditor.addEventListener("input", () => {
  textEditor.style.width = Math.max(60, textEditor.scrollWidth + 8) + "px";
});
textEditor.addEventListener("blur", () => endTextEdit(true));

host.addEventListener("dblclick", (e) => {
  if (!editable) return;
  const t = pickTarget(e.target);
  if (!t) return;
  const text = t.localName === "text" ? t : t.closest && t.closest("text");
  if (text) {
    // The first double-click opens the inspector; with it open, the next
    // edits the text in place.
    select(text);
    if (inspectorOpen) beginTextEdit(text);
    else post({ type: "editElement" });
  } else if (t.localName !== "g") {
    post({ type: "editElement" });
  }
});

// MARK: Outline — the element tree and references, for the layers list and graph.

const REF_ATTRS = [
  "fill",
  "stroke",
  "clip-path",
  "mask",
  "filter",
  "marker-start",
  "marker-mid",
  "marker-end",
];
const OUTLINE_LIMIT = 5000;
let outlineTimer = 0;

function refsOf(el) {
  const refs = [];
  for (const attr of REF_ATTRS) {
    const m = (el.getAttribute(attr) || "").match(/url\(\s*['"]?#([^'")\s]+)/);
    if (m) refs.push([attr, m[1]]);
  }
  const href = el.getAttribute("href") || el.getAttributeNS(XLINK, "href");
  if (href && href[0] === "#") refs.push(["href", href.slice(1)]);
  return refs;
}

function isHidden(el) {
  return (
    el.getAttribute("display") === "none" ||
    el.getAttribute("visibility") === "hidden" ||
    /(^|;)\s*display\s*:\s*none/.test(el.getAttribute("style") || "")
  );
}

function labelOf(el) {
  const named =
    el.getAttribute("inkscape:label") ||
    el.getAttribute("data-name") ||
    el.getAttribute("aria-label");
  if (named) return named;
  if (el.id) return el.id;
  if (el.localName === "text") {
    const t = el.textContent.trim();
    if (t) return t.length > 32 ? t.slice(0, 32) + "…" : t;
  }
  return null;
}

// Whether the inspector is showing, for double-clicks on text.
let inspectorOpen = false;
function setInspectorOpen(on) {
  inspectorOpen = !!on;
}

function scheduleOutline() {
  clearTimeout(outlineTimer);
  outlineTimer = setTimeout(sendOutline, 60);
}

// Attribute values the graph and timeline show and edit. Stops, filter
// primitives and animations report everything; other elements their paint.
const SHOWN_PROPS = ["fill", "stroke", "stroke-width", "opacity", "fill-opacity", "stroke-opacity"];
// Definitions report every attribute, for the graph's and inspector's editors.
const DEFINITION_TAGS = new Set([
  "linearGradient",
  "radialGradient",
  "pattern",
  "clipPath",
  "mask",
  "filter",
  "symbol",
  "marker",
]);
function propsOf(el) {
  const name = el.localName;
  const all =
    name === "stop" ||
    name.startsWith("fe") ||
    name.startsWith("animate") ||
    name === "set" ||
    DEFINITION_TAGS.has(name);
  const props = {};
  for (const a of el.attributes) {
    if ((all || SHOWN_PROPS.includes(a.name)) && a.value.length <= 300) props[a.name] = a.value;
  }
  return props;
}

// Sets (or, with null, removes) an attribute on any element, without changing
// the selection — for values edited in the graph and timeline.
function setAttrOn(order, name, value, coalesce) {
  const el = byOrder(order);
  if (!el || !name) return;
  try {
    if (value == null) el.removeAttribute(name);
    else setAttrNS(el, name, value);
  } catch {
    return;
  }
  if (el === root) updateIntrinsicSize();
  updateOverlay();
  commit(`Change ${label(name)}`, coalesce ? `attr:${order}:${name}` : null);
}

// What the graph shows inside definition nodes: a gradient's stop colours,
// or the effects a filter applies.
function previewOf(el) {
  const name = el.localName;
  if (name === "linearGradient" || name === "radialGradient") {
    return Array.from(el.querySelectorAll("stop")).map(
      (s) => s.getAttribute("stop-color") || (s.style && s.style.stopColor) || "#000",
    );
  }
  if (name === "filter") return Array.from(el.children).map((c) => c.localName);
  return null;
}

// CSS animations (@keyframes) running on an element, for the timeline.
function cssAnimationsOf(el) {
  if (!el.getAnimations) return null;
  let list;
  try {
    list = el.getAnimations().filter((a) => a.animationName);
  } catch {
    return null;
  }
  if (!list.length) return null;
  return list.map((a) => {
    const t = a.effect ? a.effect.getTiming() : {};
    const dur = typeof t.duration === "number" ? t.duration / 1000 : 0;
    let props = [];
    try {
      const skip = new Set(["offset", "computedOffset", "easing", "composite"]);
      const keys = new Set();
      for (const k of a.effect.getKeyframes())
        for (const p of Object.keys(k)) if (!skip.has(p)) keys.add(p);
      props = Array.from(keys);
    } catch {}
    return {
      name: a.animationName,
      props,
      duration: dur,
      delay: (t.delay || 0) / 1000,
      iterations: t.iterations === Infinity ? -1 : t.iterations || 1,
      easing: t.easing || "linear",
    };
  });
}

// Every CSS animation in the drawing; SMIL's pause and seek don't reach them.
function cssAnimations() {
  if (!root || !document.getAnimations) return [];
  try {
    return document
      .getAnimations()
      .filter((a) => a.effect && a.effect.target && root.contains(a.effect.target));
  } catch {
    return [];
  }
}

function syncCSSAnimations(seekTo) {
  for (const a of cssAnimations()) {
    try {
      a.playbackRate = animSpeed;
      if (seekTo != null) a.currentTime = seekTo * 1000;
      if (animPaused) a.pause();
      else a.play();
    } catch {}
  }
}

function sendOutline() {
  if (!root) return;
  const items = [];
  let n = 0;
  (function walk(el, parent, depth, path) {
    const order = n++; // preorder, matching orderOf() and the source scanner
    if (order > 0) {
      if (items.length >= OUTLINE_LIMIT) return;
      items.push({
        order,
        parent,
        depth,
        path: path.join("."),
        tag: el.localName,
        id: el.id || null,
        label: labelOf(el),
        hidden: isHidden(el),
        fill: el.getAttribute("fill"),
        refs: refsOf(el),
        preview: previewOf(el),
        props: propsOf(el),
        css: cssAnimationsOf(el),
        box:
          !nonVisual.has(el.localName) && !ANIM_TAGS.has(el.localName) && items.length < 3000
            ? boundsOf(el)
            : null,
      });
    }
    Array.from(el.children).forEach((c, i) => {
      if (!c.hasAttribute("data-lines-temp")) walk(c, order, depth + 1, path.concat(i));
    });
  })(root, -1, -1, []);
  post({ type: "outline", items, truncated: items.length >= OUTLINE_LIMIT });
}

function toggleHidden(order) {
  const el = byOrder(order);
  if (!el || el === root) return;
  if (isHidden(el)) {
    if (el.getAttribute("display") === "none") el.removeAttribute("display");
    if (el.getAttribute("visibility") === "hidden") el.removeAttribute("visibility");
    const style = (el.getAttribute("style") || "")
      .replace(/(^|;)\s*display\s*:\s*none\s*/g, "$1")
      .replace(/^;|;$/g, "");
    if (el.hasAttribute("style")) {
      if (style.trim()) el.setAttribute("style", style);
      else el.removeAttribute("style");
    }
    commit("Show Element");
  } else {
    el.setAttribute("display", "none");
    commit("Hide Element");
  }
  updateOverlay();
}

function uniqueID(base) {
  let i = 1;
  while (document.getElementById(`${base}-${i}`)) i++;
  return `${base}-${i}`;
}

// Points an attribute like fill or clip-path at another element, giving it an id if needed.
function setReference(order, attr, targetOrder) {
  const el = byOrder(order),
    target = byOrder(targetOrder);
  if (!el || !target || el === target) return;
  if (!target.id)
    target.id = uniqueID(target.localName.replace(/([a-z])([A-Z])/g, "$1-$2").toLowerCase());
  if (attr === "href")
    setAttrNS(el, el.hasAttributeNS(XLINK, "href") ? "xlink:href" : "href", "#" + target.id);
  else el.setAttribute(attr, `url(#${target.id})`);
  commit(`Set ${label(attr)}`);
}

function removeReference(order, attr) {
  const el = byOrder(order);
  if (!el) return;
  if (attr === "href") {
    el.removeAttribute("href");
    el.removeAttributeNS(XLINK, "href");
  } else el.removeAttribute(attr);
  commit(`Remove ${label(attr)}`);
}

// Moves elements (by preorder index) into `parentOrder`, after `afterOrder`
// (an existing child) or, when that's null, as the first children. Order in
// the document is drawing order, so "first" draws at the bottom.
function moveElements(orders, parentOrder, afterOrder) {
  const parent = byOrder(parentOrder);
  const after = afterOrder == null ? null : byOrder(afterOrder);
  const els = orders.map(byOrder).filter((el) => el && el !== root);
  if (!parent || !els.length) return;
  // Never move an element into itself or its own descendants.
  if (els.some((el) => el === parent || el.contains(parent))) return;
  const moving = new Set(els);
  // Anchor on the next sibling that isn't moving, so removing the sources can't invalidate it.
  let ref = after ? after.nextElementSibling : parent.firstElementChild;
  while (ref && moving.has(ref)) ref = ref.nextElementSibling;
  if (after && moving.has(after)) {
    let a = after.previousElementSibling;
    while (a && moving.has(a)) a = a.previousElementSibling;
    ref = a ? a.nextElementSibling : parent.firstElementChild;
    while (ref && moving.has(ref)) ref = ref.nextElementSibling;
  }
  for (const el of els) removeWithWhitespace(el);
  for (const el of els) {
    if (ref) insert(el, parent, ref);
    else insert(el, parent);
  }
  select(els[els.length - 1]);
  commit(els.length > 1 ? "Move Layers" : "Move Layer");
}

// Moves elements before or after `targetOrder`, or inside it (as the
// topmost child), for drops in the layers list.
function moveRelative(orders, targetOrder, position) {
  const target = byOrder(targetOrder);
  if (!target || target === root) return;
  const parent = position === "inside" ? target : target.parentNode;
  const els = orders.map(byOrder).filter((el) => el && el !== root && el !== target);
  if (!els.length || els.some((el) => el === parent || el.contains(parent))) return;
  for (const el of els) removeWithWhitespace(el);
  if (position === "inside") {
    for (const el of els) insert(el, parent);
  } else {
    const ref = position === "after" ? target.nextSibling : target;
    for (const el of els) insert(el, parent, ref);
  }
  select(els[els.length - 1]);
  commit(els.length > 1 ? "Move Layers" : "Move Layer");
}

// Highlights an element from the layers list without selecting it.
function hoverOrder(order) {
  if (order == null) {
    hoverBox.style.display = "none";
    return;
  }
  const el = byOrder(order);
  if (el && el !== selected) place(hoverBox, el);
  else hoverBox.style.display = "none";
}

// Renames an element by setting its id.
function renameElement(order, name) {
  const el = byOrder(order);
  if (!el || el === root) return;
  name = name.trim().replace(/\s+/g, "-");
  if (name) el.id = name;
  else el.removeAttribute("id");
  commit("Rename");
}

function copyByOrder(order) {
  const el = byOrder(order);
  return el && el !== root
    ? new XMLSerializer()
        .serializeToString(el)
        .replace(/ xmlns="http:\/\/www\.w3\.org\/2000\/svg"/, "")
    : null;
}

function deleteByOrder(order) {
  const el = byOrder(order);
  if (!el || el === root) return;
  select(el);
  deleteSelected();
}

// Renders the drawing to a PNG or JPEG data URL at `scale`, on an optional
// background colour (JPEG always gets one). Awaited by the export sheet.
// A small picture of what an element or definition does, for the graph's
// hover previews: the element alone (framed to its box), or a sample shape
// using the definition. Resolves to a PNG data URL, or null.
function previewImage(order, size) {
  return new Promise((resolve) => {
    const el = byOrder(order);
    if (!root || !el) return resolve(null);
    const name = el.localName;
    const clone = root.cloneNode(true);
    const vb = root.viewBox && root.viewBox.baseVal;
    const { w, h } = intrinsicSize();
    const area =
      vb && vb.width ? { x: vb.x, y: vb.y, w: vb.width, h: vb.height } : { x: 0, y: 0, w, h };
    const defsOnly = () => {
      // Keep the definitions (and styles); drop the artwork.
      for (const c of Array.from(clone.children))
        if (!["defs", "style"].includes(c.localName) && !DEFINITION_TAGS.has(c.localName))
          c.remove();
    };
    const add = (tag, attrs) => {
      const n = document.createElementNS(NS, tag);
      for (const [k, v] of Object.entries(attrs)) n.setAttribute(k, v);
      clone.appendChild(n);
      return n;
    };
    let box = null;
    const id = el.id;
    if ((name === "linearGradient" || name === "radialGradient" || name === "pattern") && id) {
      defsOnly();
      clone.setAttribute("viewBox", "0 0 160 100");
      add("rect", { x: 8, y: 8, width: 144, height: 84, rx: 14, fill: `url(#${id})` });
    } else if (name === "filter" && id) {
      defsOnly();
      clone.setAttribute("viewBox", "0 0 160 100");
      add("rect", {
        x: 40,
        y: 20,
        width: 80,
        height: 60,
        rx: 12,
        fill: "#f09157",
        filter: `url(#${id})`,
      });
    } else if ((name === "clipPath" || name === "mask") && id) {
      defsOnly();
      clone.setAttribute("viewBox", [area.x, area.y, area.w, area.h].join(" "));
      // A striped sample, so what's kept and what's cut both read.
      const attr = name === "mask" ? "mask" : "clip-path";
      add("rect", {
        x: area.x,
        y: area.y,
        width: area.w,
        height: area.h,
        fill: "#f09157",
        [attr]: `url(#${id})`,
      });
    } else if ((name === "symbol" || name === "marker") && id) {
      defsOnly();
      clone.setAttribute("viewBox", "0 0 100 100");
      add("use", { href: `#${id}`, width: 100, height: 100 });
    } else {
      // The element alone: everything outside it hidden, framed to its box.
      const target = ANIM_TAGS.has(name) ? el.parentNode : el;
      try {
        const b = target.getBBox();
        const m =
          root.getCTM && target.getCTM ? root.getCTM().inverse().multiply(target.getCTM()) : null;
        const pts = [
          [b.x, b.y],
          [b.x + b.width, b.y],
          [b.x, b.y + b.height],
          [b.x + b.width, b.y + b.height],
        ].map(([x, y]) => (m ? new DOMPoint(x, y).matrixTransform(m) : { x, y }));
        const xs = pts.map((p) => p.x),
          ys = pts.map((p) => p.y);
        box = {
          x: Math.min(...xs),
          y: Math.min(...ys),
          w: Math.max(...xs) - Math.min(...xs),
          h: Math.max(...ys) - Math.min(...ys),
        };
      } catch {}
      if (!box || !(box.w || box.h)) box = area;
      const pad = Math.max(box.w, box.h) * 0.08 || 1;
      clone.setAttribute(
        "viewBox",
        [box.x - pad, box.y - pad, box.w + pad * 2, box.h + pad * 2].join(" "),
      );
      // Hide everything not on the path to the target or inside it.
      const path = pathOf(target);
      let node = clone;
      const keep = new Set([clone]);
      for (const i of path) {
        node = node.children[i];
        if (!node) break;
        keep.add(node);
      }
      const walk = (n) => {
        for (const c of Array.from(n.children)) {
          if (keep.has(c)) {
            if (c !== node) walk(c);
          } else if (
            !["defs", "style"].includes(c.localName) &&
            !DEFINITION_TAGS.has(c.localName)
          ) {
            c.setAttribute("visibility", "hidden");
          }
        }
      };
      walk(clone);
    }
    const ratio = (() => {
      const v = clone
        .getAttribute("viewBox")
        .split(/[\s,]+/)
        .map(Number);
      return v[2] > 0 && v[3] > 0 ? v[2] / v[3] : 1;
    })();
    const W = ratio >= 1 ? size : Math.max(1, Math.round(size * ratio)),
      H = ratio >= 1 ? Math.max(1, Math.round(size / ratio)) : size;
    clone.setAttribute("width", W);
    clone.setAttribute("height", H);
    clone.removeAttribute("style");
    const img = new Image();
    img.onload = () => {
      try {
        const scale = 2;
        const canvas = document.createElement("canvas");
        canvas.width = W * scale;
        canvas.height = H * scale;
        canvas.getContext("2d").drawImage(img, 0, 0, canvas.width, canvas.height);
        resolve(canvas.toDataURL("image/png"));
      } catch {
        resolve(null);
      }
    };
    img.onerror = () => resolve(null);
    img.src =
      "data:image/svg+xml;charset=utf-8," +
      encodeURIComponent(new XMLSerializer().serializeToString(clone));
  });
}

// MARK: Layer thumbnails — an element on its own, framed to its box.

function elementThumbnail(order, size) {
  const el = byOrder(order);
  if (!root || !el || el === root) return Promise.resolve(null);
  const target = ANIM_TAGS.has(el.localName) ? el.parentNode : el;
  if (!target || target === root || nonVisual.has(target.localName)) return Promise.resolve(null);
  const box = userBox([target], 0.08);
  if (!box || box.w <= 0 || box.h <= 0) return Promise.resolve(null);
  const { clone } = focusedClone([target], "0");
  return renderClone(clone, box, size);
}

// MARK: Impact previews — how a node changes the drawing, for the graph.
//
// A definition: the shapes using it, without and with it. An animation: its
// element at the start, middle and end. An element: where it sits in the
// drawing. Everything else is dimmed and the affected area outlined, so the
// change stands out. Resolves to { labels, images } (PNG data URLs).

function userBox(els, pad) {
  const inv = root.getScreenCTM && root.getScreenCTM() ? root.getScreenCTM().inverse() : null;
  let u = null;
  for (const el of els) {
    const r = visualRect(el);
    if (!r || (!r.width && !r.height)) continue;
    const pts = [
      [r.left, r.top],
      [r.right, r.bottom],
    ].map(([x, y]) => (inv ? new DOMPoint(x, y).matrixTransform(inv) : { x, y }));
    const b = {
      x: Math.min(pts[0].x, pts[1].x),
      y: Math.min(pts[0].y, pts[1].y),
      r: Math.max(pts[0].x, pts[1].x),
      b: Math.max(pts[0].y, pts[1].y),
    };
    u = u
      ? {
          x: Math.min(u.x, b.x),
          y: Math.min(u.y, b.y),
          r: Math.max(u.r, b.r),
          b: Math.max(u.b, b.b),
        }
      : b;
  }
  if (!u) return null;
  const w = u.r - u.x,
    h = u.b - u.y;
  const p = Math.max(w, h) * pad + 2;
  return { x: u.x - p, y: u.y - p, w: w + p * 2, h: h + p * 2 };
}

// Copies the drawing; `affected` (live elements) stay bright, the rest dims.
function focusedClone(affected, others = "0.18") {
  const clone = root.cloneNode(true);
  const keep = new Set([clone]);
  const inside = new Set();
  for (const el of affected) {
    let node = clone;
    for (const i of pathOf(el)) {
      node = node && node.children[i];
      if (node) keep.add(node);
    }
    if (node) inside.add(node);
  }
  const walk = (n) => {
    for (const c of Array.from(n.children)) {
      if (inside.has(c)) continue;
      if (keep.has(c)) walk(c);
      else if (
        !nonVisual.has(c.localName) &&
        !["defs", "style"].includes(c.localName) &&
        !ANIM_TAGS.has(c.localName)
      )
        c.setAttribute("opacity", others);
    }
  };
  walk(clone);
  // Previews are still frames.
  for (const a of Array.from(
    clone.querySelectorAll("animate, animateTransform, animateMotion, set"),
  ))
    a.remove();
  const twin = (el) => {
    let node = clone;
    for (const i of pathOf(el)) node = node && node.children[i];
    return node;
  };
  return { clone, twin };
}

function outlineBox(clone, box) {
  const r = document.createElementNS(NS, "rect");
  const inset = Math.max(box.w, box.h) * 0.04;
  r.setAttribute("x", box.x + inset);
  r.setAttribute("y", box.y + inset);
  r.setAttribute("width", Math.max(0, box.w - inset * 2));
  r.setAttribute("height", Math.max(0, box.h - inset * 2));
  r.setAttribute("rx", inset);
  r.setAttribute("fill", "none");
  r.setAttribute(
    "stroke",
    getComputedStyle(document.documentElement).getPropertyValue("--accent") || "#d9753f",
  );
  r.setAttribute("stroke-width", "2");
  r.setAttribute("stroke-dasharray", "6 4");
  r.setAttribute("vector-effect", "non-scaling-stroke");
  clone.appendChild(r);
}

function renderClone(clone, box, size) {
  return new Promise((resolve) => {
    clone.setAttribute("viewBox", [box.x, box.y, box.w, box.h].join(" "));
    clone.setAttribute("preserveAspectRatio", "xMidYMid meet");
    const ratio = box.w > 0 && box.h > 0 ? box.w / box.h : 1;
    const W = ratio >= 1 ? size : Math.max(1, Math.round(size * ratio)),
      H = ratio >= 1 ? Math.max(1, Math.round(size / ratio)) : size;
    clone.setAttribute("width", W);
    clone.setAttribute("height", H);
    clone.removeAttribute("style");
    const img = new Image();
    img.onload = () => {
      try {
        const canvas = document.createElement("canvas");
        canvas.width = W * 2;
        canvas.height = H * 2;
        canvas.getContext("2d").drawImage(img, 0, 0, canvas.width, canvas.height);
        resolve(canvas.toDataURL("image/png"));
      } catch {
        resolve(null);
      }
    };
    img.onerror = () => resolve(null);
    img.src =
      "data:image/svg+xml;charset=utf-8," +
      encodeURIComponent(new XMLSerializer().serializeToString(clone));
  });
}

// Interpolates between two values with the same shape: numbers, number
// lists ("0 50 50") or hex colours.
function lerpValue(a, b, t) {
  if (a == null) return b;
  if (b == null) return a;
  const hex = /^#([0-9a-f]{3}|[0-9a-f]{6})$/i;
  if (hex.test(a.trim()) && hex.test(b.trim())) {
    const rgb = (h) => {
      h = h.trim().slice(1);
      if (h.length === 3)
        h = h
          .split("")
          .map((c) => c + c)
          .join("");
      return [0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16));
    };
    const x = rgb(a),
      y = rgb(b);
    return (
      "#" +
      x
        .map((v, i) =>
          Math.round(v + (y[i] - v) * t)
            .toString(16)
            .padStart(2, "0"),
        )
        .join("")
    );
  }
  const na = a.match(/-?[\d.]+(e-?\d+)?/gi),
    nb = b.match(/-?[\d.]+(e-?\d+)?/gi);
  if (na && nb && na.length === nb.length) {
    let i = 0;
    return a.replace(/-?[\d.]+(e-?\d+)?/gi, () => {
      const v = parseFloat(na[i]) + (parseFloat(nb[i]) - parseFloat(na[i])) * t;
      i++;
      return String(round(v));
    });
  }
  return t < 0.5 ? a : b;
}

// An animation's value at a fraction of one pass.
function animationValueAt(anim, t) {
  const values = anim.getAttribute("values");
  if (values) {
    const list = values
      .split(";")
      .map((v) => v.trim())
      .filter((v) => v.length);
    if (!list.length) return null;
    if (list.length === 1) return list[0];
    const pos = t * (list.length - 1);
    const i = Math.min(Math.floor(pos), list.length - 2);
    return lerpValue(list[i], list[i + 1], pos - i);
  }
  const from = anim.getAttribute("from");
  const to = anim.getAttribute("to") || anim.getAttribute("by");
  if (from == null) return t < 0.5 ? null : to;
  return lerpValue(from, to, t);
}

function impactPreview(order, size) {
  const el = byOrder(order);
  if (!root || !el) return Promise.resolve(null);
  const name = el.localName;
  const id = el.id;

  // A definition: its users without it, then with it.
  if (DEFINITION_TAGS.has(name) && id) {
    const users = Array.from(root.querySelectorAll("*")).filter((u) =>
      refsOf(u).some(([, target]) => target === id),
    );
    if (!users.length) {
      return previewImage(order, size).then((img) =>
        img ? { labels: ["Sample — nothing uses it yet"], images: [img] } : null,
      );
    }
    const box = userBox(users, name === "filter" ? 0.3 : 0.12);
    if (!box) return Promise.resolve(null);
    const without = focusedClone(users);
    for (const u of users) {
      const t = without.twin(u);
      if (!t) continue;
      for (const [attr, target] of refsOf(u)) {
        if (target !== id) continue;
        if (attr === "fill" || attr === "stroke") t.setAttribute(attr, "#c7c7cc");
        else t.removeAttribute(attr);
      }
    }
    const withIt = focusedClone(users);
    outlineBox(without.clone, box);
    outlineBox(withIt.clone, box);
    return Promise.all([
      renderClone(without.clone, box, size),
      renderClone(withIt.clone, box, size),
    ]).then((images) => ({ labels: ["Without", "With"], images }));
  }

  // An animation: its element at the start, middle and end of a pass.
  if (ANIM_TAGS.has(name)) {
    const href = el.getAttribute("href") || el.getAttributeNS(XLINK, "href");
    const target =
      href && href[0] === "#" ? root.querySelector(`[id="${href.slice(1)}"]`) : el.parentNode;
    if (!target || target === root) return Promise.resolve(null);
    const frames = [0, 0.5, 1].map((t) => {
      const f = focusedClone([target]);
      const tw = f.twin(target);
      const v = animationValueAt(el, t);
      if (tw && v != null) {
        if (name === "animateTransform") {
          const type = el.getAttribute("type") || "translate";
          const base = tw.getAttribute("transform") || "";
          tw.setAttribute("transform", `${base} ${type}(${v})`.trim());
        } else if (name !== "animateMotion") {
          const attr = el.getAttribute("attributeName");
          if (attr) tw.setAttribute(attr, v);
        }
      }
      return f.clone;
    });
    const box = userBox([target], 0.45);
    if (!box) return Promise.resolve(null);
    frames.forEach((c) => outlineBox(c, box));
    return Promise.all(frames.map((c) => renderClone(c, box, Math.round(size * 0.7)))).then(
      (images) => ({
        labels: ["Start", "Middle", "End"],
        images,
      }),
    );
  }

  // An element: where it is, the rest dimmed.
  const f = focusedClone([el]);
  const tight = userBox([el], 0.04);
  const area = userBox([root], 0.02) || tight;
  if (!tight || !area) return Promise.resolve(null);
  outlineBox(f.clone, tight);
  return renderClone(f.clone, area, size).then((img) =>
    img ? { labels: ["In the drawing"], images: [img] } : null,
  );
}

function rasterize(scale, background, type, quality) {
  return new Promise((resolve, reject) => {
    if (!root) {
      reject("No drawing");
      return;
    }
    const { w, h } = intrinsicSize();
    const clone = root.cloneNode(true);
    clone.setAttribute("width", w);
    clone.setAttribute("height", h);
    const img = new Image();
    img.onload = () => {
      try {
        const canvas = document.createElement("canvas");
        canvas.width = Math.max(1, Math.round(w * scale));
        canvas.height = Math.max(1, Math.round(h * scale));
        const ctx = canvas.getContext("2d");
        if (background || type === "image/jpeg") {
          ctx.fillStyle = background || "#ffffff";
          ctx.fillRect(0, 0, canvas.width, canvas.height);
        }
        ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
        resolve(canvas.toDataURL(type || "image/png", quality || 0.92));
      } catch (e) {
        reject(String(e));
      }
    };
    img.onerror = () => reject("This drawing couldn't be rendered.");
    img.src =
      "data:image/svg+xml;charset=utf-8," +
      encodeURIComponent(new XMLSerializer().serializeToString(clone));
  });
}

function drawingSize() {
  return root ? intrinsicSize() : null;
}

function exportPNG(scale) {
  if (!root) return;
  const { w, h } = intrinsicSize();
  const clone = root.cloneNode(true);
  clone.setAttribute("width", w);
  clone.setAttribute("height", h);
  const svg = new XMLSerializer().serializeToString(clone);
  const img = new Image();
  img.onload = () => {
    try {
      const canvas = document.createElement("canvas");
      canvas.width = Math.round(w * scale);
      canvas.height = Math.round(h * scale);
      canvas.getContext("2d").drawImage(img, 0, 0, canvas.width, canvas.height);
      post({ type: "png", data: canvas.toDataURL("image/png") });
    } catch {
      post({ type: "pngFailed", scale });
    }
  };
  img.onerror = () => post({ type: "pngFailed", scale });
  img.src = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(svg);
}

// MARK: Several selected — actions on one element apply to all of them.

// The elements an action on `order` should reach: the whole selection when
// that element is part of a multiple selection, else just it.
function targetsFor(order) {
  const el = order == null ? null : byOrder(order);
  if (!el) return [];
  const all = selection();
  return all.length > 1 && all.includes(el) ? all : [el];
}

// Wraps a per-element function so it runs over the selection as one step.
// `orderArg` is the position of its element argument.
function overSelection(name, orderArg) {
  const one = window[name];
  if (typeof one !== "function") return;
  window[name] = (...args) => {
    const targets = targetsFor(args[orderArg]);
    if (targets.length <= 1) return one(...args);
    const keep = selection();
    inBatch(() => {
      for (const t of targets) {
        if (!root.contains(t)) continue;
        const a = args.slice();
        a[orderArg] = orderOf(t); // orders shift as things are added
        one(...a);
      }
    });
    selectMany(keep.filter((e) => root.contains(e)));
  };
}
overSelection("addAnimation", 0);
overSelection("toggleHidden", 0);
overSelection("setReference", 0);
overSelection("addDefinition", 1); // each gets its own, fitted to it

// MARK: Preview mode — locked: nothing changes, and ⌘-click follows links.

const EDITING_FUNCTIONS = [
  "setAttr",
  "setPaint",
  "removeAttr",
  "setText",
  "addShape",
  "addImage",
  "deleteSelected",
  "duplicateSelected",
  "reorder",
  "groupSelected",
  "flipSelected",
  "ungroupSelected",
  "pasteMarkup",
  "setBounds",
  "setRotation",
  "fitViewBoxToContent",
  "addDefinition",
  "removeAllReferences",
  "addAnimation",
  "beginTextEdit",
  "setAttrOn",
  "toggleHidden",
  "setReference",
  "removeReference",
  "moveElements",
  "moveRelative",
  "renameElement",
  "deleteByOrder",
  "addStop",
  "addDefinitionShape",
  "invertMask",
  "setCornerRadii",
  "editDefinitionOnCanvas",
  "removeUnusedDefinitions",
];
for (const name of EDITING_FUNCTIONS) {
  const f = window[name];
  if (typeof f === "function") window[name] = (...args) => (editable ? f(...args) : undefined);
}

function setEditable(on) {
  editable = !!on;
  document.body.classList.toggle("preview", !editable);
  if (!editable) {
    if (typeof endTextEdit === "function" && editingText) endTextEdit(true);
    setTool("select");
    select(null);
    hoverBox.style.display = "none";
  }
  updateDocFrame();
}

function linkAt(t) {
  const a = t && t.closest ? t.closest("a") : null;
  if (!a || !root || !root.contains(a)) return null;
  return a.getAttribute("href") || a.getAttributeNS(XLINK, "href");
}

host.addEventListener("click", (e) => {
  if (editable) return;
  const href = linkAt(e.target);
  if (href && e.metaKey) {
    post({ type: "openLink", url: href });
    e.preventDefault();
  }
});

// Links show a pointer in preview mode while ⌘ is held.
window.addEventListener("mousemove", (e) => {
  document.body.classList.toggle("over-link", !editable && e.metaKey && !!linkAt(e.target));
});

// The entry points the app calls by name (CanvasController.call), listed so
// they read as used.
Object.assign(globalThis, {
  addAnimation,
  addDefinition,
  addDefinitionShape,
  addImage,
  addShape,
  addStop,
  animPlay,
  animSetSpeed,
  animStop,
  copyByOrder,
  copySelected,
  deleteByOrder,
  drawingSize,
  duplicateSelected,
  editDefinitionOnCanvas,
  elementThumbnail,
  exportPNG,
  fitViewBoxToContent,
  flipSelected,
  groupSelected,
  hoverOrder,
  impactPreview,
  invertMask,
  moveElements,
  moveRelative,
  pasteMarkup,
  rasterize,
  removeAllReferences,
  removeAttr,
  removeReference,
  removeUnusedDefinitions,
  renameElement,
  reorder,
  selectByOrder,
  setAccent,
  setAttr,
  setAttrOn,
  setBackground,
  setBounds,
  setCornerRadii,
  setEditable,
  setInsets,
  setInspectorOpen,
  setMinimapShift,
  setPaint,
  setReference,
  setRotation,
  setSVG,
  setText,
  setTimelineActive,
  setTimelineLoop,
  showDocumentFrame,
  toggleHidden,
  ungroupSelected,
  zoomBy,
  zoomToFit,
});

post({ type: "ready" });

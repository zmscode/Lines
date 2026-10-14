"use strict";
const NS = "http://www.w3.org/2000/svg";
const XLINK = "http://www.w3.org/1999/xlink";
const host = document.getElementById("host");
const selBox = document.getElementById("sel");
const hoverBox = document.getElementById("hover");
const post = (m) => window.webkit.messageHandlers.bridge.postMessage(m);

let root = null; // live <svg> element
let prefix = ""; // text before the root element (prolog, doctype, comments)
let suffix = "\n"; // text after the root element
let selected = null;
let lastGood = null;
let zoom = 1; // display scale; never written to the file
let autoFit = true; // keep fitting to the window until someone zooms by hand
const MIN_ZOOM = 0.05,
  MAX_ZOOM = 64;

// MARK: Rendering

function setSVG(text) {
  const doc = new DOMParser().parseFromString(text, "image/svg+xml");
  const err = doc.querySelector("parsererror");
  if (err || !doc.documentElement || doc.documentElement.localName !== "svg") {
    const msg = err
      ? err.textContent
          .replace(/\s+/g, " ")
          .replace(/^.*?error[^:]*:\s*/i, "")
          .trim()
      : "The root element must be <svg>.";
    post({ type: "error", message: msg || "This SVG couldn't be parsed." });
    return;
  }
  const oldPath = selected ? pathOf(selected) : null;
  const start = text.search(/<svg[\s>/]/);
  const end = text.lastIndexOf("</svg>");
  prefix = start > 0 ? text.slice(0, start) : "";
  suffix = end >= 0 ? text.slice(end + 6) : (text.match(/\s*$/) || ["\n"])[0];
  const node = document.importNode(doc.documentElement, true);
  host.replaceChildren(node);
  root = node;
  lastGood = text;
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
    } catch (e) {}
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
  return prefix + new XMLSerializer().serializeToString(root) + suffix;
}

function commit(action, coalesce) {
  const svg = serialize();
  lastGood = svg;
  scheduleThumbnail();
  scheduleOutline();
  post({ type: "changed", svg, action, coalesce: coalesce || null });
  reportSelection(true);
}

// `color` is used by the custom background.
function setBackground(kind, color) {
  document.body.className = kind;
  document.body.style.background = kind === "custom" && color ? color : "";
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

function select(el, fromSource) {
  selected = el && el !== root ? el : null;
  updateOverlay();
  reportSelection(false, fromSource);
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
    fromSource: !!fromSource || !!afterEdit,
  });
}

function place(box, el) {
  if (!el || !el.getBoundingClientRect) {
    box.style.display = "none";
    return;
  }
  const r = el.getBoundingClientRect();
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
function updateOverlay() {
  place(selBox, selected);
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
  if (e.button !== 0 || !root) return;
  const t = pickTarget(e.target);
  let target = t;
  // Clicking inside an already-selected group moves the group; double-clicking drills in.
  if (t && selected && selected.localName === "g" && selected.contains(t) && e.detail < 2)
    target = selected;
  select(target);
  if (!target) return;
  const parent = target.parentNode;
  drag = {
    el: target,
    parent,
    start: toLocal(parent, e.clientX, e.clientY),
    cx: e.clientX,
    cy: e.clientY,
    geo: snapshotGeometry(target),
    moved: false,
  };
  e.preventDefault();
});

document.addEventListener("mousedown", (e) => {
  // Clicks on the handles or the text editor keep the selection.
  if (e.target === textEditor || selBox.contains(e.target)) return;
  if (!host.contains(e.target) && e.button === 0) select(null);
});

window.addEventListener("mousemove", (e) => {
  if (!drag) {
    const t = pickTarget(e.target);
    if (t && t !== selected) place(hoverBox, t);
    else hoverBox.style.display = "none";
    return;
  }
  if (!drag.moved && Math.hypot(e.clientX - drag.cx, e.clientY - drag.cy) < 3) return;
  drag.moved = true;
  hoverBox.style.display = "none";
  const p = toLocal(drag.parent, e.clientX, e.clientY);
  let dx = p.x - drag.start.x,
    dy = p.y - drag.start.y;
  if (e.shiftKey) {
    if (Math.abs(dx) > Math.abs(dy)) dy = 0;
    else dx = 0;
  }
  applyOffset(drag.el, drag.geo, dx, dy);
  updateOverlay();
});

window.addEventListener("mouseup", () => {
  if (drag && drag.moved) commit("Move");
  drag = null;
});

document.addEventListener("mouseleave", () => {
  hoverBox.style.display = "none";
});

document.addEventListener("keydown", (e) => {
  if (!root) return;
  if (e.key === "Escape") {
    selected ? selectParent() : select(null);
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
    applyOffset(selected, snapshotGeometry(selected), d[0], d[1]);
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
  } catch (e) {
    return;
  }
  if (el === root) updateIntrinsicSize();
  updateOverlay();
  commit(`Change ${label(name)}`, coalesce ? `attr:${name}` : null);
}

// Sets a paint and its opacity together (fill + fill-opacity), as one undo step.
function setPaint(name, color, opacity, coalesce) {
  const el = selected || root;
  if (!el) return;
  el.setAttribute(name, color);
  const opacityAttr = name + "-opacity";
  if (opacity == null || opacity >= 0.999) el.removeAttribute(opacityAttr);
  else el.setAttribute(opacityAttr, Math.round(opacity * 100) / 100);
  updateOverlay();
  commit(`Change ${label(name)}`, coalesce ? `paint:${name}` : null);
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

function label(name) {
  return name
    .replace(/^xlink:/, "")
    .split("-")
    .map((s) => s[0].toUpperCase() + s.slice(1))
    .join(" ");
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
  if (!selected) return;
  const parent = selected.parentNode;
  removeWithWhitespace(selected);
  select(parent !== root ? parent : null);
  commit("Delete");
}

function duplicateSelected() {
  if (!selected) return;
  const copy = selected.cloneNode(true);
  if (copy.id) copy.removeAttribute("id");
  insert(copy, selected.parentNode, selected.nextSibling);
  applyOffset(copy, snapshotGeometry(copy), 10, 10);
  select(copy);
  commit("Duplicate");
}

function reorder(mode) {
  if (!selected) return;
  const el = selected,
    parent = el.parentNode;
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
  return selected
    ? new XMLSerializer()
        .serializeToString(selected)
        .replace(/ xmlns="http:\/\/www\.w3\.org\/2000\/svg"/, "")
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

function render() {
  frame = 0;
  host.style.transform = `translate3d(${tx}px, ${ty}px, 0)`;
  updateOverlay();
  updateMinimap();
}
function scheduleRender() {
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
function setInsets(left, right, top, bottom) {
  insets = { left, right, top, bottom };
  minimap.style.left = left + 12 + "px";
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
  scheduleRender();
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
    if (!(e.button === 1 || (e.button === 0 && spaceDown))) return;
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
    scheduleRender();
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
  scheduleRender();
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

function snapshotShape(el) {
  const attrs = {};
  for (const a of GEOMETRY[el.localName] || []) attrs[a] = el.getAttribute(a);
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
  if (!GEOMETRY[el.localName]) return false;
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
  let b;
  try {
    b = el.getBBox();
  } catch (e) {
    return null;
  }
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

function setRotation(degrees) {
  if (!selected) return;
  const r = selected.getBoundingClientRect();
  rotateAround(
    selected,
    snapshotShape(selected),
    degrees - rotationOf(selected),
    r.left + r.width / 2,
    r.top + r.height / 2,
  );
  updateOverlay();
  commit("Rotate", "rotation");
}

// Sets the viewBox to the bounds of everything drawn, trimming empty space.
function fitViewBoxToContent() {
  if (!root) return;
  let b;
  try {
    b = root.getBBox();
  } catch (e) {
    return;
  }
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
  const t = pickTarget(e.target);
  if (!t) return;
  const text = t.localName === "text" ? t : t.closest && t.closest("text");
  if (text) {
    select(text);
    beginTextEdit(text);
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

function scheduleOutline() {
  clearTimeout(outlineTimer);
  outlineTimer = setTimeout(sendOutline, 60);
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
      });
    }
    Array.from(el.children).forEach((c, i) => walk(c, order, depth + 1, path.concat(i)));
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
    } catch (e) {
      post({ type: "pngFailed", scale });
    }
  };
  img.onerror = () => post({ type: "pngFailed", scale });
  img.src = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(svg);
}

post({ type: "ready" });

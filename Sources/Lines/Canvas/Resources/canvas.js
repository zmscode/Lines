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

function fitScale() {
  if (!root || window.innerWidth < 2 || window.innerHeight < 2) return zoom;
  const { w, h } = intrinsicSize();
  const fit = Math.min((window.innerWidth - PAD * 2) / w, (window.innerHeight - PAD * 2) / h);
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
    ax = window.innerWidth / 2;
    ay = window.innerHeight / 2;
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
  tx = (window.innerWidth - W) / 2;
  ty = (window.innerHeight - H) / 2;
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
    if (e.code === "Space" && !e.repeat) {
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

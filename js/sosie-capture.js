/**
 * sosie-capture.js - DOM snapshot extractor for sosie.
 *
 * Standalone function that can be pasted into any browser console
 * (Chromium, Firefox, Safari). Returns a JSON snapshot matching the
 * sosie schema: a resolved layout+style tree suitable for structural
 * comparison.
 *
 * Usage:
 *   JSON.stringify(sosieCapture(), null, 2)
 *   // or with custom property whitelist:
 *   JSON.stringify(sosieCapture(["display", "color"]), null, 2)
 */

function sosieCapture(properties) {
  "use strict";

  var DEFAULT_PROPERTIES = [
    "display", "visibility", "opacity",
    "color", "background-color",
    "font-family", "font-size", "font-weight", "line-height",
    "text-align", "text-decoration",
    "border-top-width", "border-top-style", "border-top-color",
    "border-right-width", "border-right-style", "border-right-color",
    "border-bottom-width", "border-bottom-style", "border-bottom-color",
    "border-left-width", "border-left-style", "border-left-color",
    "border-radius",
    "box-shadow",
    "overflow-x", "overflow-y",
    "z-index", "cursor",
    "text-align-last", "text-decoration-skip-ink", "text-underline-offset",
    "text-shadow", "text-combine-upright",
    "text-emphasis-style", "text-emphasis-color", "text-emphasis-position",
    "-webkit-text-stroke-width", "-webkit-text-stroke-color",
    "font-palette", "writing-mode", "direction", "appearance",
    "accent-color", "image-rendering",
    "outline-width", "outline-style", "outline-color", "outline-offset",
    "fill", "stroke", "stroke-width"
  ];

  var props = properties || DEFAULT_PROPERTIES;

  // Freeze the page: disable transitions and animations to prevent
  // layout shifts during the DOM walk.
  var freezeStyle = document.createElement("style");
  freezeStyle.textContent =
    "* { transition: none !important; animation: none !important; }";
  // document.head is null on XML documents without an explicit <head> and on
  // SVG-rooted documents; fall back to the document element.
  (document.head || document.documentElement).appendChild(freezeStyle);

  // Force a reflow so the freeze takes effect before we measure.
  document.documentElement.offsetHeight;

  var paintOrder = 0;

  function getStyles(computedStyle) {
    var styles = {};
    for (var i = 0; i < props.length; i++) {
      styles[props[i]] = computedStyle.getPropertyValue(props[i]);
    }
    return styles;
  }

  function getBounds(rect) {
    return {
      x: rect.x,
      y: rect.y,
      w: rect.width,
      h: rect.height
    };
  }

  function capturePseudo(el, selector) {
    var style = window.getComputedStyle(el, selector);
    var content = style.getPropertyValue("content");
    // Skip pseudo-elements with no visible content.
    if (content === "none" || content === "" || content === '""') {
      return null;
    }
    // Pseudo-elements share the parent's bounding rect (no independent
    // geometry available from standard Web APIs).
    return {
      tag: selector,
      attributes: [],
      bounds: getBounds(el.getBoundingClientRect()),
      styles: getStyles(style),
      text: content,
      paintOrder: paintOrder++,
      children: []
    };
  }

  // UA shadow pseudo-elements worth capturing, keyed by element type.
  // getComputedStyle cannot reliably tell whether these generate a box:
  // it returns a full declaration for almost any (element, pseudo) pair,
  // so there is no trustworthy existence signal. We therefore do NOT
  // attempt existence detection. Instead we capture a fixed,
  // element-type-gated set unconditionally. Because sosie compares
  // before-vs-after on the SAME element, a pseudo that generates no real
  // box resolves identically on both sides and contributes no spurious
  // diff; the gating only bounds tree size. Modern ::slider-* selectors
  // are unsupported in Chromium (empty declaration), so the legacy
  // -webkit- names are used. See plans/pseudo-element-capture.md.
  var TEXT_INPUT_TYPES = {
    text: 1, search: 1, url: 1, tel: 1, email: 1, password: 1, number: 1
  };

  function applicablePseudos(el) {
    switch (el.tagName) {
      case "INPUT":
        var t = (el.type || "text").toLowerCase();
        if (t === "file") return ["::file-selector-button"];
        if (t === "range")
          return ["::-webkit-slider-runnable-track", "::-webkit-slider-thumb"];
        if (TEXT_INPUT_TYPES[t]) return ["::placeholder"];
        return [];
      case "TEXTAREA": return ["::placeholder"];
      case "PROGRESS":
        return ["::-webkit-progress-bar", "::-webkit-progress-value"];
      case "METER":
        return ["::-webkit-meter-bar", "::-webkit-meter-inner-element"];
      // Permission elements (PEPC): the type-specific tags (<geolocation>,
      // <camera>, <microphone>) and the generic <permission>. Their
      // ::permission-icon reflects cascaded fill/stroke via getComputedStyle
      // (verified: <geolocation> icon fill = author value, not the default).
      case "GEOLOCATION":
      case "CAMERA":
      case "MICROPHONE":
      case "PERMISSION": return ["::permission-icon"];
      default: return [];
    }
  }

  // Capture a UA shadow pseudo-element unconditionally (no content gate;
  // these structural pseudos carry content "normal"/"none").
  function captureUAPseudo(el, selector) {
    return {
      tag: selector,
      attributes: [],
      bounds: getBounds(el.getBoundingClientRect()),
      styles: getStyles(window.getComputedStyle(el, selector)),
      text: null,
      paintOrder: paintOrder++,
      children: []
    };
  }

  function captureElement(el) {
    var rect = el.getBoundingClientRect();
    var computed = window.getComputedStyle(el);
    var node = {
      tag: el.tagName,
      attributes: [],
      bounds: getBounds(rect),
      styles: getStyles(computed),
      text: null,
      paintOrder: paintOrder++,
      children: []
    };

    // Capture significant attributes for identification.
    if (el.id) {
      node.attributes.push(["id", el.id]);
    }
    if (el.className && typeof el.className === "string") {
      node.attributes.push(["class", el.className]);
    }

    // Capture pseudo-elements.
    var before = capturePseudo(el, "::before");
    if (before) {
      node.children.push(before);
    }

    // UA shadow pseudo-elements (element-type-gated, unconditional).
    var uaPseudos = applicablePseudos(el);
    for (var pi = 0; pi < uaPseudos.length; pi++) {
      node.children.push(captureUAPseudo(el, uaPseudos[pi]));
    }

    // Walk child nodes: elements and text nodes.
    for (var i = 0; i < el.childNodes.length; i++) {
      var child = el.childNodes[i];
      if (child.nodeType === Node.ELEMENT_NODE) {
        node.children.push(captureElement(child));
      } else if (child.nodeType === Node.TEXT_NODE) {
        var text = child.textContent;
        // Skip whitespace-only text nodes.
        if (text.trim().length > 0) {
          // Text nodes inherit bounds and styles from their parent
          // element (text nodes have no independent geometry in the
          // standard Web APIs).
          node.children.push({
            tag: "#text",
            attributes: [],
            bounds: getBounds(rect),
            styles: getStyles(computed),
            text: text,
            paintOrder: paintOrder++,
            children: []
          });
        }
      }
    }

    // Capture ::after pseudo-element after real children.
    var after = capturePseudo(el, "::after");
    if (after) {
      node.children.push(after);
    }

    return node;
  }

  var root = captureElement(document.documentElement);

  // Remove the freeze stylesheet from its actual parent (may be head or the
  // document element, per the fallback above).
  freezeStyle.remove();

  return {
    version: 1,
    url: window.location.href,
    viewport: [window.innerWidth, window.innerHeight],
    colorScheme: window.matchMedia("(prefers-color-scheme: dark)").matches
      ? "dark"
      : "light",
    root: root
  };
}

/* doc.js — sidebar outline + live search + resize/collapse for rendered workspace docs.
   Linked by generated docs: <script src="ASSETS/doc.js" defer></script>
   Zero deps, works from file://. Builds a TOC from headings (h2–h4) and glossary
   terms (.gterm); filters live as you type. Keys: "/" focus search, Esc clear,
   "t" toggle sidebar. Drag the right edge to resize (double-click to reset);
   width + collapsed state persist via localStorage when available. */
(function () {
  "use strict";
  function ready(fn){ document.readyState !== "loading" ? fn() : document.addEventListener("DOMContentLoaded", fn); }
  function slug(s){ return (s.toLowerCase().replace(/[^\w]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 60)) || "s"; }
  function lsGet(k){ try { return localStorage.getItem(k); } catch (e) { return null; } }
  function lsSet(k, v){ try { localStorage.setItem(k, v); } catch (e) {} }

  ready(function () {
    var article = document.querySelector("article");
    if (!article) return;
    var SEL = "h2, h3, h4, .gterm";
    var heads = Array.prototype.slice.call(article.querySelectorAll(SEL));
    if (heads.length < 3) return;

    var used = {};
    heads.forEach(function (h) {
      if (!h.id) {
        var base = slug(h.textContent), id = base, i = 2;
        while (used[id] || document.getElementById(id)) id = base + "-" + (i++);
        used[id] = 1; h.id = id;
      }
    });

    var sections = heads.map(function (h) {
      var members = [h], n = h.nextElementSibling;
      while (n && !n.matches(SEL)) { members.push(n); n = n.nextElementSibling; }
      return { head: h, members: members, text: members.map(function (m) { return m.textContent; }).join(" ").toLowerCase(), link: null };
    });

    // ---- build sidebar ----
    var side = document.createElement("aside"); side.className = "doc-sidebar";
    var head = document.createElement("div"); head.className = "doc-sidebar-head";
    var h1 = document.querySelector("article h1");
    var title = document.createElement("div"); title.className = "doc-sidebar-title";
    title.textContent = h1 ? h1.textContent : "Outline";
    var hideBtn = document.createElement("button"); hideBtn.type = "button"; hideBtn.className = "doc-hide";
    hideBtn.textContent = "‹ hide"; hideBtn.title = "Hide outline (t)";
    head.appendChild(title); head.appendChild(hideBtn);

    var search = document.createElement("input"); search.type = "search"; search.className = "doc-search";
    search.placeholder = "Filter…  ( / )"; search.setAttribute("aria-label", "Filter this page");
    var count = document.createElement("div"); count.className = "doc-count";
    var nav = document.createElement("nav"); nav.className = "doc-toc";
    side.appendChild(head); side.appendChild(search); side.appendChild(count); side.appendChild(nav);

    sections.forEach(function (s) {
      var lvl = s.head.matches(".gterm") ? "t" : s.head.tagName.toLowerCase();
      var a = document.createElement("a");
      a.href = "#" + s.head.id; a.className = "toc-" + lvl; a.textContent = s.head.textContent.trim();
      nav.appendChild(a); s.link = a;
    });

    document.body.insertBefore(side, document.body.firstChild);
    document.body.classList.add("has-doc-sidebar");

    // resize handle + floating show button (siblings of the sidebar)
    var handle = document.createElement("div"); handle.className = "doc-resize"; handle.title = "Drag to resize · double-click to reset";
    var showBtn = document.createElement("button"); showBtn.type = "button"; showBtn.className = "doc-show";
    showBtn.textContent = "☰ outline"; showBtn.title = "Show outline (t)";
    document.body.appendChild(handle); document.body.appendChild(showBtn);

    // ---- resize ----
    var MINW = 160, MAXW = 720;
    function setW(px){ px = Math.max(MINW, Math.min(MAXW, px)); document.body.style.setProperty("--sbw", px + "px"); lsSet("teachSbw", px); }
    var savedW = lsGet("teachSbw"); if (savedW) setW(parseFloat(savedW));
    handle.addEventListener("mousedown", function (e) {
      e.preventDefault(); document.body.classList.add("doc-resizing");
      function mm(ev){ setW(ev.clientX); }
      function mu(){ document.removeEventListener("mousemove", mm); document.removeEventListener("mouseup", mu); document.body.classList.remove("doc-resizing"); }
      document.addEventListener("mousemove", mm); document.addEventListener("mouseup", mu);
    });
    handle.addEventListener("dblclick", function () { document.body.style.removeProperty("--sbw"); lsSet("teachSbw", ""); });

    // ---- collapse ----
    function setCollapsed(c){ document.body.classList.toggle("doc-collapsed", c); lsSet("teachSbHidden", c ? "1" : "0"); }
    hideBtn.addEventListener("click", function () { setCollapsed(true); });
    showBtn.addEventListener("click", function () { setCollapsed(false); });
    if (lsGet("teachSbHidden") === "1") setCollapsed(true);

    // ---- filter ----
    function apply(q) {
      q = q.trim().toLowerCase(); var shown = 0;
      sections.forEach(function (s) {
        var hit = !q || s.text.indexOf(q) >= 0;
        s.members.forEach(function (m) { m.style.display = hit ? "" : "none"; });
        if (s.link) s.link.style.display = hit ? "" : "none";
        if (hit) shown++;
      });
      count.textContent = q ? (shown + " match" + (shown === 1 ? "" : "es")) : (sections.length + " entries");
    }
    apply("");
    search.addEventListener("input", function () { apply(search.value); });

    // ---- keyboard ----
    document.addEventListener("keydown", function (e) {
      if (e.target === search) { if (e.key === "Escape") { search.value = ""; apply(""); search.blur(); } return; }
      if (e.key === "/") { e.preventDefault(); if (document.body.classList.contains("doc-collapsed")) setCollapsed(false); search.focus(); }
      else if (e.key === "t" || e.key === "T") { setCollapsed(!document.body.classList.contains("doc-collapsed")); }
    });

    // ---- active-section highlight ----
    if ("IntersectionObserver" in window) {
      var byId = {}; sections.forEach(function (s) { byId[s.head.id] = s; });
      var io = new IntersectionObserver(function (ents) {
        ents.forEach(function (en) {
          if (!en.isIntersecting) return;
          var s = byId[en.target.id]; if (!s || !s.link) return;
          var cur = nav.querySelector(".active"); if (cur) cur.classList.remove("active");
          s.link.classList.add("active");
        });
      }, { rootMargin: "0px 0px -80% 0px" });
      heads.forEach(function (h) { io.observe(h); });
    }
  });
})();

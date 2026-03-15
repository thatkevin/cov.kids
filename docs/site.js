// cov.kids — Scroll-triggered fade-in + venue filter
document.addEventListener('DOMContentLoaded', function () {

  // --- Category collapse (localStorage-persisted) ---
  var CAT_STORAGE_KEY = 'ck-hidden-cats';

  function getHiddenCats() {
    try { return JSON.parse(localStorage.getItem(CAT_STORAGE_KEY) || '[]'); } catch(e) { return []; }
  }
  function setHiddenCats(cats) {
    try { localStorage.setItem(CAT_STORAGE_KEY, JSON.stringify(cats)); } catch(e) {}
  }

  function updateToggleBtn(section) {
    var btn = section.querySelector('.category-toggle');
    if (btn) btn.textContent = section.classList.contains('is-collapsed') ? '+' : '−';
  }

  document.querySelectorAll('.category-section[data-category]').forEach(function(section) {
    var cat = section.dataset.category;
    if (getHiddenCats().indexOf(cat) !== -1) section.classList.add('is-collapsed');
    updateToggleBtn(section);
  });

  document.addEventListener('click', function(e) {
    var btn = e.target.closest('.category-toggle');
    if (!btn) return;
    var section = btn.closest('.category-section[data-category]');
    if (!section) return;
    var cat = section.dataset.category;
    var hidden = getHiddenCats();
    var idx = hidden.indexOf(cat);
    if (idx === -1) { hidden.push(cat); } else { hidden.splice(idx, 1); }
    setHiddenCats(hidden);
    section.classList.toggle('is-collapsed', idx === -1);
    updateToggleBtn(section);
    var g = document.querySelector('.events-grid');
    if (g) { lastColCount = -1; buildEventColumns(g.getBoundingClientRect().width); }
  });

  // --- Venue filter ---
  var filterEl = document.getElementById('venue-filter');
  if (filterEl) {
    filterEl.addEventListener('click', function (e) {
      var btn = e.target.closest('.venue-chip');
      if (!btn) return;

      var selected = btn.dataset.venue;

      filterEl.querySelectorAll('.venue-chip').forEach(function (c) {
        c.classList.toggle('active', c === btn);
      });

      document.querySelectorAll('.event-card[data-venue]').forEach(function (card) {
        card.style.display = (!selected || card.dataset.venue === selected) ? '' : 'none';
      });

      document.querySelectorAll('.category-section').forEach(function (section) {
        var hasVisible = Array.from(section.querySelectorAll('.event-card')).some(function (c) {
          return c.style.display !== 'none';
        });
        section.style.display = hasVisible ? '' : 'none';
      });
    });
  }

  // --- Column distribution (greedy bin-pack, sections stay whole) ---
  // Width is supplied by ResizeObserver to avoid a forced reflow.
  var lastColCount = -1;
  function buildEventColumns(w) {
    var grid = document.querySelector('.events-grid');
    if (!grid) return;

    var colCount = w >= 1000 ? 4 : w >= 700 ? 3 : w >= 460 ? 2 : 1;
    if (colCount === lastColCount) return;
    lastColCount = colCount;

    // Collect sections, pulling them back out of any existing col wrappers
    var sections = [];
    Array.from(grid.children).forEach(function (child) {
      if (child.classList.contains('events-col')) {
        Array.from(child.children).forEach(function (s) { sections.push(s); });
      } else {
        sections.push(child);
      }
    });
    if (!sections.length) return;

    // Clear grid
    while (grid.firstChild) grid.removeChild(grid.firstChild);

    if (colCount === 1) {
      sections.forEach(function (s) { grid.appendChild(s); });
      return;
    }

    // Create column wrappers
    var cols = [], weights = new Array(colCount).fill(0);
    for (var i = 0; i < colCount; i++) {
      var col = document.createElement('div');
      col.className = 'events-col';
      grid.appendChild(col);
      cols.push(col);
    }

    // Greedy: place each section into the lightest column
    sections.forEach(function (s) {
      var count = parseInt(s.getAttribute('data-count') || '1', 10);
      var minIdx = weights.indexOf(Math.min.apply(null, weights));
      cols[minIdx].appendChild(s);
      weights[minIdx] += count;
    });
  }

  // ResizeObserver fires after layout — no forced reflow.
  var grid = document.querySelector('.events-grid');
  if (grid) {
    new ResizeObserver(function (entries) {
      buildEventColumns(entries[0].contentRect.width);
    }).observe(grid);
  }

  // Top banner — measure after fonts load for pixel-perfect seamless loop
  var bannerTrack = document.querySelector('.top-banner-track');
  if (bannerTrack) {
    var bannerSet = bannerTrack.querySelector('.top-banner-set');
    document.fonts.ready.then(function () {
      requestAnimationFrame(function () {
      var setWidth = bannerSet.offsetWidth;
      if (!setWidth) return;
      var pos = 0;
      bannerTrack.style.willChange = 'transform';
      // Remove CSS animation now that JS takes over
      bannerTrack.style.animation = 'none';
      (function tick() {
        pos -= 0.5;
        if (pos <= -setWidth) pos += setWidth;
        bannerTrack.style.transform = 'translateX(' + pos + 'px)';
        requestAnimationFrame(tick);
      })();
      }); // end rAF
    }); // end fonts.ready
  }

  // Fade-in on scroll
  var elements = document.querySelectorAll('.fade-in');
  if (elements.length) {
    elements.forEach(function (el, i) {
      el.style.transitionDelay = (i % 10) * 0.04 + 's';
    });

    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add('visible');
          observer.unobserve(entry.target);
        }
      });
    }, {
      threshold: 0.1,
      rootMargin: '0px 0px -40px 0px'
    });

    elements.forEach(function (el) {
      observer.observe(el);
    });
  }

});

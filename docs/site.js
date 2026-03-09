// cov.kids — Scroll-triggered fade-in + venue filter
document.addEventListener('DOMContentLoaded', function () {

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
  function buildEventColumns() {
    var grid = document.querySelector('.events-grid');
    if (!grid) return;

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

    var w = grid.offsetWidth;
    var colCount = w >= 1000 ? 4 : w >= 700 ? 3 : w >= 460 ? 2 : 1;

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

  requestAnimationFrame(buildEventColumns);

  var _colTimer;
  window.addEventListener('resize', function () {
    clearTimeout(_colTimer);
    _colTimer = setTimeout(function () { requestAnimationFrame(buildEventColumns); }, 200);
  }, { passive: true });

  // Top banner — measure after fonts load for pixel-perfect seamless loop
  var bannerTrack = document.querySelector('.top-banner-track');
  if (bannerTrack) {
    var bannerSet = bannerTrack.querySelector('.top-banner-set');
    document.fonts.ready.then(function () {
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
    });
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

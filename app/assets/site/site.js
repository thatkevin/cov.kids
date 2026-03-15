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

  function makeWrapper(height) {
    var w = document.createElement('div');
    w.className        = 'event-list-clip';
    w.style.overflow   = 'hidden';
    w.style.height     = height;
    w.style.transition = 'height 0.25s ease';
    return w;
  }

  // If an animation is in progress, immediately resolve it and return true.
  function resolveAnimation(list) {
    var w = list.parentNode;
    if (!w || !w.classList.contains('event-list-clip')) return false;
    w.parentNode.insertBefore(list, w);
    w.parentNode.removeChild(w);
    return true;
  }

  function animateCollapse(list) {
    if (resolveAnimation(list)) { list.style.display = 'none'; return; }
    var w = makeWrapper(list.offsetHeight + 'px');
    list.parentNode.insertBefore(w, list);
    w.appendChild(list);
    requestAnimationFrame(function() {
      requestAnimationFrame(function() {
        w.style.height = '0';
        w.addEventListener('transitionend', function done() {
          w.removeEventListener('transitionend', done);
          w.parentNode.insertBefore(list, w);
          w.parentNode.removeChild(w);
          list.style.display = 'none';
        });
      });
    });
  }

  function animateExpand(list) {
    if (resolveAnimation(list)) { list.style.display = ''; return; }
    list.style.display = '';
    var naturalHeight = list.offsetHeight;
    var w = makeWrapper('0');
    list.parentNode.insertBefore(w, list);
    w.appendChild(list);
    requestAnimationFrame(function() {
      requestAnimationFrame(function() {
        w.style.height = naturalHeight + 'px';
        w.addEventListener('transitionend', function done() {
          w.removeEventListener('transitionend', done);
          w.parentNode.insertBefore(list, w);
          w.parentNode.removeChild(w);
        });
      });
    });
  }

  // On load: apply stored collapsed state instantly (no animation)
  document.querySelectorAll('.category-section[data-category]').forEach(function(section) {
    var cat = section.dataset.category;
    if (getHiddenCats().indexOf(cat) !== -1) {
      section.classList.add('is-collapsed');
      var list = section.querySelector('.event-list');
      if (list) list.style.display = 'none';
    }
    updateToggleBtn(section);
  });

  document.addEventListener('click', function(e) {
    if (!e.target.closest('.category-header')) return;
    var section = e.target.closest('.category-section[data-category]');
    if (!section) return;
    var list = section.querySelector('.event-list');
    if (!list) return;
    var cat = section.dataset.category;
    var hidden = getHiddenCats();
    var idx = hidden.indexOf(cat);
    var collapsing = idx === -1;
    if (collapsing) { hidden.push(cat); } else { hidden.splice(idx, 1); }
    setHiddenCats(hidden);
    section.classList.toggle('is-collapsed', collapsing);
    updateToggleBtn(section);
    if (collapsing) { animateCollapse(list); } else { animateExpand(list); }
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
        bannerTrack.style.animation = 'none';
        (function tick() {
          pos -= 0.5;
          if (pos <= -setWidth) pos += setWidth;
          bannerTrack.style.transform = 'translateX(' + pos + 'px)';
          requestAnimationFrame(tick);
        })();
      });
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

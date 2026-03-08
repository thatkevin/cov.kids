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

  // Byline fade-out on scroll
  var byline = document.querySelector('.byline');
  if (byline) {
    window.addEventListener('scroll', function () {
      if (window.scrollY > 30) {
        byline.classList.add('scrolled');
      } else {
        byline.classList.remove('scrolled');
      }
    }, { passive: true });
  }

  // Continuous marquee for bottom banner
  var track = document.querySelector('.banner-track');
  if (track) {
    var set = track.querySelector('.banner-set');
    if (set) {
      // Clone until we have enough to fill viewport + scroll
      var needed = Math.ceil((window.innerWidth * 3) / set.offsetWidth) + 1;
      for (var i = 1; i < needed; i++) {
        track.appendChild(set.cloneNode(true));
      }

      var setWidth = set.offsetWidth;
      var pos = 0;
      var speed = 0.5; // pixels per frame

      function animateBanner() {
        pos -= speed;
        if (pos <= -setWidth) {
          pos += setWidth;
        }
        track.style.transform = 'translateX(' + pos + 'px)';
        requestAnimationFrame(animateBanner);
      }
      requestAnimationFrame(animateBanner);
    }
  }
});

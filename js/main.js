// Shiverbug Studios site interactions

// This file is pure ASCII. It is a classic script with no charset of its own, so
// it inherits whatever encoding the page was decoded as; a literal curly quote
// here is only ever as safe as the last <meta charset> to reference it. Every
// apostrophe that reaches the page is built from its code point instead.
const RSQUO = String.fromCharCode(8217);

// ----- nav: scrolled state + mobile menu -----
// Guarded because co-dev.html is a bare meta-refresh stub with no header at all.
// Reaching for the burger there threw before anything else in this file ran,
// which cost that page its footer year and its click tracking.
(() => {
  const nav = document.getElementById('nav');
  const burger = document.getElementById('navBurger');
  const navLinks = document.getElementById('navLinks');
  if (!nav) return;

  // Run once up front as well: a page restored mid-scroll (back button, reload)
  // fires no scroll event, and would otherwise show the bare hero bar over content.
  const syncScrolled = () => nav.classList.toggle('is-scrolled', window.scrollY > 10);
  window.addEventListener('scroll', syncScrolled, { passive: true });
  syncScrolled();

  if (!burger || !navLinks) return;

  // Below the breakpoint the open menu covers the page, so the rest of it goes
  // inert while it is up: no tabbing behind it, and screen readers skip it. The
  // same bargain the gallery viewer makes. On desktop the links are just part of
  // the header, nothing is covered, and none of this applies.
  const isOverlay = () => getComputedStyle(burger).display !== 'none';

  let inerted = [];
  const setBackgroundInert = (on) => {
    inerted.forEach((el) => { el.inert = false; });
    inerted = [];
    if (!on) return;
    inerted = [...document.body.children].filter((el) => el !== nav && !el.inert);
    inerted.forEach((el) => { el.inert = true; });
  };

  const setMenu = (open) => {
    nav.classList.toggle('is-open', open);
    burger.setAttribute('aria-expanded', String(open));
    setBackgroundInert(open && isOverlay());
  };

  burger.addEventListener('click', () => setMenu(!nav.classList.contains('is-open')));

  navLinks.addEventListener('click', (e) => {
    if (e.target.closest('a')) setMenu(false);
  });

  // The menu overlays the page, so it has to be dismissable without hunting for
  // the burger again: Escape (focus goes back to the button that opened it), or a
  // tap anywhere outside it.
  document.addEventListener('keydown', (e) => {
    if (!nav.classList.contains('is-open')) return;
    if (e.key === 'Escape') {
      setMenu(false);
      burger.focus();
    } else if (e.key === 'Tab' && isOverlay()) {
      // Keep focus looping through everything in the bar, in DOM order: the
      // brand, the links, then the burger (which sits after the links in the
      // markup). Building the list in any other order lets Tab walk straight out.
      const els = [...nav.querySelectorAll('a[href], button')].filter((el) => el.offsetParent !== null);
      if (!els.length) return;
      const first = els[0], last = els[els.length - 1];
      if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
      else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
      else if (!nav.contains(document.activeElement)) { e.preventDefault(); first.focus(); }
    }
  });

  document.addEventListener('pointerdown', (e) => {
    if (nav.classList.contains('is-open') && !nav.contains(e.target)) setMenu(false);
  });

  // Widening past the breakpoint turns the overlay back into a plain header row.
  // Leaving it "open" would strand the inert flag on everything else on the page.
  window.addEventListener('resize', () => {
    if (nav.classList.contains('is-open') && !isOverlay()) setMenu(false);
  });
})();

// ----- tool chips: fall back to the plain name if a logo is missing -----
// The marks are supplied per vendor and some of them we don't hold yet. A chip
// with no logo file should look like the chip always did, not like a broken
// image, and checking naturalWidth covers the ones that already failed before
// this file ran.
document.querySelectorAll('.tool__logo').forEach((img) => {
  const drop = () => img.remove();
  if (img.complete && img.naturalWidth === 0) drop();
  else img.addEventListener('error', drop);
});

// ----- games page: the gameplay clip starts itself once it's on screen -----
// Same bargain the co-development carousels make: it never runs under reduced
// motion, and it doesn't fetch a byte until the clip is actually in view. The
// clip sits right under the page heading, so "in view" is usually "on load",
// which is why the files are encoded lean (a few MB, not the 12-14 MB they
// were) and why a visitor who has asked their browser to save data, or is on a
// slow connection, gets the poster and the play button instead of a download.
// The clip keeps its native controls, so 2.2.2 Pause, Stop, Hide is covered
// without the custom button the carousel clips need.
(() => {
  const clip = document.getElementById('trailer');
  if (!clip) return;
  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const conn = navigator.connection;
  const frugal = !!conn && (conn.saveData || /(^|-)2g$|^3g$/.test(conn.effectiveType || ''));
  if (reduceMotion || frugal || !('IntersectionObserver' in window)) return;

  const io = new IntersectionObserver((entries) => {
    entries.forEach(({ isIntersecting }) => {
      // remembered so the pause handler below can tell a visitor's pause from
      // the one this observer fires on the way off screen
      clip.dataset.onScreen = String(isIntersecting);
      // A visitor who hits pause has said what they want. Don't override it the
      // next time the clip scrolls back into view.
      if (isIntersecting && clip.dataset.userPaused !== 'true') {
        if (clip.preload === 'none') clip.preload = 'auto';
        clip.play().catch(() => {});
      } else {
        clip.pause();
      }
    });
  }, { threshold: 0.25 });
  io.observe(clip);

  // 'pause' fires for scrolling off screen too, so only count it as the
  // visitor's doing while the clip is in view.
  clip.addEventListener('pause', () => {
    if (clip.dataset.onScreen !== 'false') clip.dataset.userPaused = 'true';
  });
  clip.addEventListener('play', () => { clip.dataset.userPaused = 'false'; });
})();

// ----- reveal on scroll -----
// The stylesheet only hides .reveal elements under html.js, which a one-line
// script in each page's head sets, and it carries a failsafe that fades them
// in anyway after a few seconds. This class switches that failsafe off: it is
// only set once this file has got far enough to take over, so if main.js is
// blocked, 404s or dies on a SyntaxError, nothing stays invisible.
document.documentElement.classList.add('reveal-ready');
const revealEls = document.querySelectorAll('.reveal');
if ('IntersectionObserver' in window) {
  const io = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add('is-visible');
        io.unobserve(entry.target);
      }
    });
  }, { threshold: 0.12, rootMargin: '0px 0px -40px 0px' });
  revealEls.forEach((el) => io.observe(el));
} else {
  revealEls.forEach((el) => el.classList.add('is-visible'));
}

// ----- tiles for people whose profile isn't written yet -----
// The build emits these as plain <div>/<span>, never links, so there is no dead
// end to walk into with or without JS. Here we upgrade them into real buttons
// that reveal a short note, the same bargain the gallery viewer makes: the
// affordance only appears once something is behind it.
(() => {
  let n = 0;
  const wire = (el, note) => {
    note.id = note.id || ('soon-' + (++n));
    el.setAttribute('role', 'button');
    el.setAttribute('tabindex', '0');
    el.setAttribute('aria-expanded', 'false');
    el.setAttribute('aria-controls', note.id);
    const toggle = () => {
      const open = note.hidden;
      note.hidden = !open;
      el.setAttribute('aria-expanded', String(open));
    };
    el.addEventListener('click', toggle);
    el.addEventListener('keydown', (e) => {
      if (e.key !== 'Enter' && e.key !== ' ') return;
      e.preventDefault();   // stop Space scrolling the page out from under it
      toggle();
    });
  };

  // team grids: the note is already in the markup, under the name and role
  document.querySelectorAll('.member--unfinished').forEach((tile) => {
    const note = tile.querySelector('.member__soon');
    if (note) wire(tile, note);
  });

  // co-dev crew chips: a chip is too small to hold the note, so each crew row
  // gets one shared line beneath it. Several chips share that one note, so this
  // can't use the plain toggle above: clicking a second person has to swap the
  // note over to them, not close it.
  document.querySelectorAll('.svc__crew').forEach((row) => {
    const chips = [...row.querySelectorAll('.person--unfinished')];
    if (!chips.length) return;
    const note = document.createElement('p');
    note.className = 'member__soon svc__crew-note';
    note.hidden = true;
    note.id = 'crew-soon-' + (++n);
    row.insertAdjacentElement('afterend', note);

    let openChip = null;
    const setOpen = (chip) => {
      openChip = chip;
      chips.forEach((c) => c.setAttribute('aria-expanded', String(c === chip)));
      note.hidden = !chip;
      if (chip) {
        const first = chip.querySelector('strong').textContent.trim().split(' ')[0];
        note.textContent = 'We haven' + RSQUO + 't written up ' + first + RSQUO +
                           's profile yet. Check back soon.';
      }
    };

    chips.forEach((chip) => {
      chip.setAttribute('role', 'button');
      chip.setAttribute('tabindex', '0');
      chip.setAttribute('aria-expanded', 'false');
      chip.setAttribute('aria-controls', note.id);
      const activate = () => setOpen(openChip === chip ? null : chip);
      chip.addEventListener('click', activate);
      chip.addEventListener('keydown', (e) => {
        if (e.key !== 'Enter' && e.key !== ' ') return;
        e.preventDefault();
        activate();
      });
    });
  });
})();

// ----- FAQ: one answer open at a time -----
// <details name="faq"> already does this natively - grouped like radio buttons,
// no script involved. Older browsers ignore the attribute and let every answer
// sit open at once, so only those get the hand-rolled version. Running both
// would mean two things racing to close the same panel.
if (!('name' in document.createElement('details'))) {
  document.querySelectorAll('details[name]').forEach((d) => {
    d.addEventListener('toggle', () => {
      if (!d.open) return;
      const group = d.getAttribute('name');
      document.querySelectorAll('details[name="' + group + '"]').forEach((other) => {
        if (other !== d) other.open = false;
      });
    });
  });
}

// ----- gallery carousels: arrows, drag-to-flick -----
document.querySelectorAll('.carousel').forEach((carousel) => {
  const track = carousel.querySelector('.carousel__track');
  if (!track || track.children.length === 0) return;
  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const behavior = reduceMotion ? 'auto' : 'smooth';

  // looping clips only load and play while on screen (and never with reduced motion)
  const vids = track.querySelectorAll('video');
  if (vids.length && !reduceMotion && 'IntersectionObserver' in window) {
    const vio = new IntersectionObserver((entries) => {
      entries.forEach(({ isIntersecting, target }) => {
        // remembered so the pause control knows which clips to resume
        target.dataset.onScreen = String(isIntersecting);
        if (isIntersecting && target.dataset.userPaused !== 'true') target.play().catch(() => {});
        else target.pause();
      });
    }, { threshold: 0.25 });
    vids.forEach((v) => vio.observe(v));
  }

  // 2.2.2 Pause, Stop, Hide. The clips start on their own and loop well past five
  // seconds, so each one carries its own control, sitting on the clip it governs
  // instead of in a single strip further up the page where it read as unrelated
  // furniture. Built here rather than in the markup for the same reason the
  // viewer's role/tabindex are: with no JS nothing ever starts playing, and a
  // pause button over a still frame is a control for nothing.
  // Deliberately not persisted: remembering it would mean writing to the
  // visitor's device, and the privacy policy promises we store nothing.
  if (!reduceMotion) {
    vids.forEach((v) => {
      const slot = v.closest('.carousel__slot');
      if (!slot) return;
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'clip-toggle';
      btn.innerHTML =
        '<svg class="icon-pause" viewBox="0 0 16 16" aria-hidden="true"><rect x="3" y="2" width="4" height="12" rx="1" fill="currentColor"/><rect x="9" y="2" width="4" height="12" rx="1" fill="currentColor"/></svg>' +
        '<svg class="icon-play" viewBox="0 0 16 16" aria-hidden="true"><path d="M4 2.5v11l9-5.5z" fill="currentColor"/></svg>';
      // aria-pressed carries the state to assistive tech and swaps the icon in
      // CSS, so the two can't drift apart the way a separate class would.
      const sync = () => {
        const paused = v.dataset.userPaused === 'true';
        btn.setAttribute('aria-pressed', String(paused));
        btn.setAttribute('aria-label', paused ? 'Resume this clip' : 'Pause this clip');
      };
      btn.addEventListener('click', () => {
        const paused = v.dataset.userPaused !== 'true';
        v.dataset.userPaused = String(paused);
        if (paused) v.pause();
        else if (v.dataset.onScreen === 'true') v.play().catch(() => {});
        sync();
      });
      sync();
      slot.appendChild(btn);
    });
  }

  const step = () => Math.max(track.clientWidth * 0.8, 200);
  const prevBtn = carousel.querySelector('.carousel__btn--prev');
  const nextBtn = carousel.querySelector('.carousel__btn--next');
  prevBtn?.addEventListener('click', () => track.scrollBy({ left: -step(), behavior }));
  nextBtn?.addEventListener('click', () => track.scrollBy({ left: step(), behavior }));

  // grey out the arrows at either end of the strip
  const updateBtns = () => {
    const max = track.scrollWidth - track.clientWidth - 1;
    if (prevBtn) prevBtn.disabled = track.scrollLeft <= 1;
    if (nextBtn) nextBtn.disabled = track.scrollLeft >= max;
  };
  updateBtns();
  track.addEventListener('scroll', updateBtns, { passive: true });
  window.addEventListener('resize', updateBtns);

  // drag to flick through with a mouse (touch already scrolls natively)
  // The artwork tiles are links, and a mouse drag on a link starts the browser's
  // own link drag: that fires pointercancel and swallows the pointerup, which
  // used to leave the strip "held" and scrolling with every mouse move until the
  // next click. So the native drag is cancelled outright, a cancel ends the drag
  // the same way a release does, and a plain button check catches anything that
  // still slips through.
  let dragging = false, dragged = false, startX = 0, startScroll = 0;
  const endDrag = () => {
    if (!dragging) return;
    dragging = false;
    track.classList.remove('is-dragging');
  };
  track.addEventListener('dragstart', (e) => e.preventDefault());
  track.addEventListener('pointerdown', (e) => {
    if (e.pointerType !== 'mouse' || e.button !== 0) return;
    dragging = true; dragged = false;
    startX = e.clientX; startScroll = track.scrollLeft;
    track.classList.add('is-dragging');
  });
  window.addEventListener('pointermove', (e) => {
    if (!dragging) return;
    if (!(e.buttons & 1)) { endDrag(); return; }
    const dx = e.clientX - startX;
    if (Math.abs(dx) > 5) dragged = true;
    track.scrollLeft = startScroll - dx;
  });
  window.addEventListener('pointerup', endDrag);
  window.addEventListener('pointercancel', endDrag);
  window.addEventListener('blur', endDrag);
  // a drag shouldn't count as a click on the artwork link
  track.addEventListener('click', (e) => {
    if (dragged) { e.preventDefault(); e.stopPropagation(); dragged = false; }
  }, true);
});

// ----- lightbox: click gallery art to view large, arrows to browse -----
(() => {
  const carousels = document.querySelectorAll('.carousel');
  if (!carousels.length) return;

  const overlay = document.createElement('div');
  overlay.className = 'lightbox';
  overlay.setAttribute('role', 'dialog');
  overlay.setAttribute('aria-modal', 'true');
  overlay.setAttribute('aria-label', 'Gallery viewer');
  overlay.innerHTML = `
    <button class="lightbox__close" type="button" aria-label="Close viewer">&times;</button>
    <button class="lightbox__btn lightbox__btn--prev" type="button" aria-label="Previous piece">&lsaquo;</button>
    <figure class="lightbox__figure">
      <!-- No src or href until there is something to put in them: an empty one
           is not "nothing", it resolves to the page's own URL and fetches it. -->
      <img class="lightbox__img" alt="">
      <video class="lightbox__video" controls loop playsinline hidden></video>
      <figcaption class="lightbox__caption"><strong class="lightbox__cap-title" hidden></strong><span class="lightbox__cap-text"></span><a class="lightbox__credit" hidden></a></figcaption>
    </figure>
    <button class="lightbox__btn lightbox__btn--next" type="button" aria-label="Next piece">&rsaquo;</button>`;
  document.body.appendChild(overlay);

  const imgEl = overlay.querySelector('.lightbox__img');
  const vidEl = overlay.querySelector('.lightbox__video');
  const capEl = overlay.querySelector('.lightbox__cap-text');
  const titleEl = overlay.querySelector('.lightbox__cap-title');
  const creditEl = overlay.querySelector('.lightbox__credit');
  let items = [], index = 0, lastFocus = null;

  const show = (i) => {
    index = (i + items.length) % items.length;
    const item = items[index];
    if (item.video) {
      imgEl.hidden = true; imgEl.removeAttribute('src');
      if (vidEl.getAttribute('src') !== item.video) vidEl.src = item.video;
      vidEl.hidden = false;
      vidEl.play().catch(() => {});
    } else {
      vidEl.pause(); vidEl.hidden = true;
      imgEl.hidden = false;
      imgEl.src = item.href;
      imgEl.alt = item.alt;
    }
    titleEl.textContent = item.title || '';
    titleEl.hidden = !item.title;
    // the write-up if the piece has one, otherwise the plain visual description
    capEl.textContent = item.desc || item.alt;
    if (item.credit) {
      creditEl.textContent = 'Work by ' + item.credit;
      // Credits for people without a written-up profile are plain labels, so
      // there is no href to hang on them. An <a> without one isn't focusable,
      // which is exactly right: it goes nowhere.
      if (item.creditHref) creditEl.href = item.creditHref;
      else creditEl.removeAttribute('href');
      creditEl.hidden = false;
    } else {
      creditEl.hidden = true;
    }
  };
  // everything you can tab to inside the viewer, in document order
  const focusables = () => [...overlay.querySelectorAll('button, [href], video[controls]')]
    .filter((el) => !el.hidden && el.offsetParent !== null);

  // while the viewer is open the rest of the page is inert: no tabbing behind it,
  // and screen readers skip it too
  let inerted = [];
  const setBackgroundInert = (on) => {
    if (on) {
      inerted = [...document.body.children].filter((el) => el !== overlay && !el.inert);
      inerted.forEach((el) => { el.inert = true; });
    } else {
      inerted.forEach((el) => { el.inert = false; });
      inerted = [];
    }
  };

  // The carousel clips behind the viewer are still "on screen" as far as their
  // observer knows, so they would keep decoding under the overlay. Park them
  // while it is up and hand them back on close.
  let parked = [];
  const parkClips = () => {
    parked = [...document.querySelectorAll('.carousel__slot > video')].filter((v) => !v.paused);
    parked.forEach((v) => v.pause());
  };
  const unparkClips = () => {
    parked.forEach((v) => {
      if (v.dataset.userPaused !== 'true' && v.dataset.onScreen === 'true') v.play().catch(() => {});
    });
    parked = [];
  };

  const open = (list, i, fromEl) => {
    items = list; lastFocus = fromEl;
    parkClips();
    show(i);
    overlay.classList.add('is-open');
    document.body.style.overflow = 'hidden';
    setBackgroundInert(true);
    // .lightbox is visibility:hidden until .is-open lands, and you can't focus what
    // isn't visible yet. Reading a layout property forces the style recalc right now
    // so the focus sticks. (requestAnimationFrame is too early: it runs before the
    // recalc, so the button is still hidden when the callback fires.)
    void overlay.offsetWidth;
    overlay.querySelector('.lightbox__close').focus();
  };
  const close = () => {
    overlay.classList.remove('is-open');
    document.body.style.overflow = '';
    setBackgroundInert(false);
    imgEl.removeAttribute('src');
    vidEl.pause();
    unparkClips();
    if (lastFocus) lastFocus.focus();
  };

  overlay.querySelector('.lightbox__close').addEventListener('click', close);
  overlay.querySelector('.lightbox__btn--prev').addEventListener('click', () => show(index - 1));
  overlay.querySelector('.lightbox__btn--next').addEventListener('click', () => show(index + 1));
  overlay.addEventListener('click', (e) => { if (e.target === overlay) close(); });
  document.addEventListener('keydown', (e) => {
    if (!overlay.classList.contains('is-open')) return;
    if (e.key === 'Escape') close();
    else if (e.key === 'ArrowLeft') show(index - 1);
    else if (e.key === 'ArrowRight') show(index + 1);
    else if (e.key === 'Tab') {
      // keep focus looping inside the viewer
      const els = focusables();
      if (!els.length) return;
      const first = els[0], last = els[els.length - 1];
      if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
      else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
      else if (!overlay.contains(document.activeElement)) { e.preventDefault(); first.focus(); }
    }
  });

  carousels.forEach((carousel) => {
    const track = carousel.querySelector('.carousel__track');
    if (!track) return;

    // Artwork tiles are links, so they already tab. Clip tiles are a bare
    // <video> with no control on them, which left them mouse-only: 2.1.1 wants
    // the same viewer reachable from the keyboard. The role and tabindex go on
    // here rather than in the markup because without JS there is no viewer to
    // open, and advertising a button that does nothing is worse than neither.
    track.querySelectorAll('.carousel__slot > video').forEach((v) => {
      v.setAttribute('role', 'button');
      v.setAttribute('tabindex', '0');
      if (!v.hasAttribute('aria-label')) v.setAttribute('aria-label', 'Open clip in the gallery viewer');
    });
    track.addEventListener('keydown', (e) => {
      if (e.key !== 'Enter' && e.key !== ' ') return;
      const v = e.target.closest('video[role="button"]');
      if (!v) return;
      e.preventDefault();
      v.click();
    });

    track.addEventListener('click', (e) => {
      const a = e.target.closest('a[href]');
      if (a && a.classList.contains('carousel__credit')) return; // credit chips navigate normally
      const v = a ? null : e.target.closest('video');
      if ((!a && !v) || !track.contains(a || v)) return;
      e.preventDefault();
      // unique pieces (images and clips) in display order
      const seen = new Set(), list = [];
      track.querySelectorAll('.carousel__slot').forEach((slot) => {
        const credit = slot.querySelector('.carousel__credit');
        const base = {
          credit: credit ? credit.textContent.trim() : '',
          creditHref: credit ? credit.getAttribute('href') : '',
          title: slot.dataset.title || '',
          desc: slot.dataset.desc || ''
        };
        const art = slot.querySelector('a[href]:not(.carousel__credit)');
        const clip = slot.querySelector('video');
        if (art) {
          const href = art.getAttribute('href');
          if (seen.has(href)) return;
          seen.add(href);
          list.push({ ...base, href, alt: art.querySelector('img') ? art.querySelector('img').alt : '' });
        } else if (clip) {
          const src = clip.getAttribute('src');
          if (seen.has(src)) return;
          seen.add(src);
          list.push({ ...base, video: src, alt: clip.getAttribute('aria-label') || '' });
        }
      });
      const key = a ? a.getAttribute('href') : v.getAttribute('src');
      open(list, Math.max(0, list.findIndex((x) => (x.href || x.video) === key)), a || v);
    });
  });
})();

// ----- analytics: count the handful of moments that actually matter -----
// GoatCounter events, on the same cookieless endpoint as the page view. Nothing
// here identifies anyone: it is a label and a count, so it stays inside what the
// privacy policy promises and still needs no consent banner. count.js loads
// async, so every call is guarded rather than assumed.
const countEvent = (name) => {
  const gc = window.goatcounter;
  if (gc && typeof gc.count === 'function') {
    gc.count({ path: name, title: name, event: true });
  }
};

const slug = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

// ----- contact form: show the co-development fields only when they apply -----
// The picker is also the form's _subject, so one control decides both what the
// visitor is asked for and what the email is labelled in the inbox.
//
// `required` is added and removed alongside the fields rather than sitting in the
// markup, because a required control inside a display:none block refuses to submit
// and points its validation bubble at something nobody can see. If this script
// never runs, the group stays visible and stays optional - the right way round to
// fail, since a visitor is then never held at a question they can't answer.
const CODEV_TOPIC = 'Co-development enquiry';
const topicSelect = document.getElementById('cdTopic');
const codevFields = [...document.querySelectorAll('#codevForm .field--codev')];
const codevRequired = ['cdStudio', 'cdHelp'];

const syncCodevFields = () => {
  if (!topicSelect) return;
  const on = topicSelect.value === CODEV_TOPIC;
  codevFields.forEach((f) => {
    f.hidden = !on;
    // Disabled as well as hidden, because FormData still collects a hidden input.
    // Without this every message about joining the studio arrives with four empty
    // co-development fields stapled to it.
    f.querySelectorAll('input, select, textarea').forEach((el) => { el.disabled = !on; });
  });
  codevRequired.forEach((id) => {
    document.getElementById(id)?.toggleAttribute('required', on);
  });
  const msg = document.getElementById('cdMsg');
  if (msg) {
    msg.placeholder = on
      ? "What you're building, what you need a hand with, and anything else that helps us scope it."
      : 'A paragraph is plenty.';
  }
};

if (topicSelect) {
  topicSelect.addEventListener('change', syncCodevFields);
  syncCodevFields();
}

// Set from a link that already knows what it is about - the package cards and the
// co-dev buttons. It never overwrites a topic the visitor has already picked.
const setTopic = (value) => {
  if (!topicSelect || !value) return;
  if (topicSelect.value && topicSelect.value !== value) return;
  topicSelect.value = value;
  syncCodevFields();
};

document.addEventListener('click', (e) => {
  const a = e.target.closest('a[href]');
  if (!a) return;
  const href = a.getAttribute('href') || '';
  if (a.hasAttribute('download')) {
    countEvent('download-' + href.split('/').pop());
  } else if (a.dataset.cta) {
    // The "start a conversation" buttons used to be mailto links, whose ?subject=
    // was the only thing telling a publishing enquiry apart from a co-dev one in
    // the inbox. They point at the forms now, so carry that label across by hand:
    // the general form has a single _subject covering everything that lands in it.
    // The co-dev form sets its own, more specific subject and is left alone.
    countEvent('cta-' + slug(a.dataset.cta));
    setTopic(a.dataset.topic);
    const subject = document.querySelector('#contactForm input[name="_subject"]');
    if (subject) subject.value = a.dataset.cta;
    // Same bargain the package cards make: arrive with the opening line already
    // written rather than on a blank box. Never overwrites anything already typed.
    if (a.dataset.prefill) {
      const msg = document.querySelector('#contactForm textarea[name="message"]');
      if (msg && !msg.value.trim()) msg.value = a.dataset.prefill;
    }
  } else if (a.dataset.package) {
    // A package card was clicked. It's a plain #contact link, so the scroll
    // happens on its own; all this adds is arriving with the size already picked
    // and an opening line written, so nobody lands on a blank form wondering
    // which of the three they were just reading about.
    countEvent('package-' + slug(a.dataset.package));
    // A package card is a co-development enquiry by definition, so the picker above
    // it should already say so by the time the scroll lands.
    setTopic(CODEV_TOPIC);
    const form = document.getElementById('codevForm');
    if (form) {
      const size = form.querySelector('select[name="package"]');
      if (size) {
        const want = [...size.options].find((o) => o.text.indexOf(a.dataset.package) === 0);
        if (want) size.value = want.value || want.text;
      }
      // never overwrite something they have already started typing
      const msg = form.querySelector('textarea[name="message"]');
      if (msg && !msg.value.trim()) {
        msg.value = 'We' + RSQUO + 're interested in the ' + a.dataset.package +
                    ' package (' + a.dataset.packageName + ').\n\nHere' + RSQUO +
                    's what we' + RSQUO + 're building: ';
      }
    }
  } else if (href.startsWith('mailto:')) {
    // the ?subject= is what tells press enquiries apart from general
    const subject = href.split('subject=')[1] || 'general';
    countEvent('mailto-' + slug(decodeURIComponent(subject)));
  }
});

// ----- forms: post in the background so nobody gets bounced off the site -----
// Both endpoints send Access-Control-Allow-Origin, so we can read the result.
// Without JS the forms still submit natively, which is why the action stays on them.
const enhanceForm = (form, sentMsg, errorMsg, eventName) => {
  if (!form) return;
  // Success is polite, failure is assertive: a send that didn't go through is
  // the one thing the visitor has to act on. Both regions exist, empty, from
  // the moment the page loads. A live region inserted with its text already in
  // it is one most screen readers never announce, because there was no change
  // for them to notice - the region has to be there first and then be filled.
  const politeBox = document.createElement('div');
  politeBox.setAttribute('role', 'status');
  const alertBox = document.createElement('div');
  alertBox.setAttribute('role', 'alert');
  form.parentNode.insertBefore(politeBox, form);
  form.parentNode.insertBefore(alertBox, form);

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const btn = form.querySelector('button[type="submit"]');
    politeBox.replaceChildren();
    alertBox.replaceChildren();
    btn.disabled = true;
    // A portfolio link typed as "artstation.com/me" is what people actually
    // write. The field takes plain text so the browser doesn't refuse it; the
    // scheme goes on here, so the inbox still gets something clickable.
    const link = form.querySelector('input[name="link"]');
    if (link && link.value.trim() && !/^[a-z][a-z0-9+.-]*:/i.test(link.value.trim())) {
      link.value = 'https://' + link.value.trim();
    }
    const note = document.createElement('p');
    try {
      const res = await fetch(form.action, {
        method: 'POST',
        body: new FormData(form),
        headers: { 'Accept': 'application/json' }
      });
      if (res.ok) {
        // Both are read before reset(), or they would describe an empty form.
        const sent = typeof sentMsg === 'function' ? sentMsg() : sentMsg;
        const label = typeof eventName === 'function' ? eventName() : eventName;
        note.className = 'form-note form-sent';
        note.textContent = sent;
        form.reset();
        // reset() puts the topic back to "Pick one", so the co-development
        // fields have to be hidden (and un-required) again to match it.
        if (form.id === 'codevForm') syncCodevFields();
        if (label) countEvent(label);
      } else {
        note.className = 'form-note form-error';
        note.textContent = errorMsg;
      }
    } catch (err) {
      note.className = 'form-note form-error';
      note.textContent = errorMsg;
    }
    (note.classList.contains('form-error') ? alertBox : politeBox).appendChild(note);
    btn.disabled = false;
  });
};

enhanceForm(
  document.getElementById('contactForm'),
  "Message sent! We'll get back to you soon.",
  "Hmm, that didn't send. Try again, or email us directly above.",
  'contact-form-sent'
);

// One form, five topics. The two working days is a promise worth making to a
// studio with a budget and a deadline; it is not one to make to someone sending a
// portfolio speculatively, so that path gets a warm answer without a clock on it.
enhanceForm(
  document.getElementById('codevForm'),
  () => (topicSelect && topicSelect.value === CODEV_TOPIC
    ? "Thanks. That's with us, and you'll hear back within a couple of working days."
    : "Thanks, that's with us. We read everything that lands here."),
  "Hmm, that didn't send. Try again, or email us directly above.",
  () => 'enquiry-sent-' + slug((topicSelect && topicSelect.value) || 'unspecified')
);

enhanceForm(
  document.getElementById('newsletterForm'),
  'Almost there. Check your inbox and confirm your address.',
  "Hmm, that didn't go through. Give it another go in a moment.",
  'newsletter-signup'
);

// ----- footer year -----
const year = document.getElementById('year');
if (year) year.textContent = new Date().getFullYear();

// ----- press kit: copy the boilerplate -----
// Progressive enhancement. The buttons are in the markup, but a press kit whose
// copy blocks can only be selected by hand is a press kit people retype, so if
// the clipboard API is unavailable the buttons come out rather than sit there
// doing nothing.
(() => {
  const buttons = [...document.querySelectorAll('[data-copy]')];
  if (!buttons.length) return;

  if (!navigator.clipboard) {
    buttons.forEach((btn) => { btn.remove(); });
    return;
  }

  buttons.forEach((btn) => {
    const source = document.querySelector(btn.dataset.copy);
    if (!source) { btn.remove(); return; }

    const label = btn.textContent;
    let reset;

    // aria-live would announce on every press; changing the button's own label
    // is announced once, by the control the user just activated.
    const say = (text, done) => {
      btn.textContent = text;
      btn.classList.toggle('is-done', !!done);
      clearTimeout(reset);
      reset = setTimeout(() => {
        btn.textContent = label;
        btn.classList.remove('is-done');
      }, 2500);
    };

    btn.addEventListener('click', async () => {
      try {
        await navigator.clipboard.writeText(source.textContent.trim());
        say('Copied', true);
      } catch {
        // Clipboard permission can be refused (locked-down enterprise policy,
        // an embedded webview, an insecure origin). Telling someone to press
        // Ctrl+C is only useful if the thing they want is already selected, so
        // do that part for them.
        const range = document.createRange();
        range.selectNodeContents(source);
        const selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
        say('Selected - press Ctrl+C');
      }
    });
  });
})();

// ----- package cards lean towards the pointer -----
// The one piece of the motion polish that needs a script, because it has to
// measure where the pointer is. Everything else is CSS, documented in the
// MOTION POLISH section at the foot of css/style.css.
//
// The transform itself lives in the stylesheet; this only supplies the two
// angles, so the lean and the hover lift compose in one place instead of the
// script fighting the CSS over style.transform.
//
// Its own IIFE, like the rest of this file: one shared top-level scope means a
// bare `const` here would collide with any other of the same name and take the
// whole file down with it.
(() => {
  const still = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const fine = window.matchMedia('(hover: hover) and (pointer: fine)').matches;
  if (still || !fine) return;   // nothing to lean towards on a touchscreen
  const MAX = 1.5;   // degrees, per side. Four and a half read as a gimmick.
  document.querySelectorAll('.pkg').forEach((card) => {
    card.addEventListener('pointermove', (e) => {
      const box = card.getBoundingClientRect();
      const x = (e.clientX - box.left) / box.width - .5;
      const y = (e.clientY - box.top) / box.height - .5;
      card.style.setProperty('--rx', (x * MAX * 2).toFixed(2) + 'deg');
      card.style.setProperty('--ry', (-y * MAX * 2).toFixed(2) + 'deg');
    });
    const reset = () => {
      card.style.setProperty('--rx', '0deg');
      card.style.setProperty('--ry', '0deg');
    };
    card.addEventListener('pointerleave', reset);
    // a card can be left by tabbing away as well as by moving the pointer off it
    card.addEventListener('blur', reset, true);
  });
})();

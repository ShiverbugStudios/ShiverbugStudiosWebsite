// Shiverbug Studios. Everything here is an improvement on a page that already
// works without it: the footage shows its poster, work links open the full
// image, and the forms post normally.
(function () {
  "use strict";

  var still = window.matchMedia("(prefers-reduced-motion: reduce)");

  // ---- Menu -----------------------------------------------------------------
  // The phone menu is a <details>, so it opens and closes without script. This
  // adds what a menu is expected to do besides: Escape and a tap outside close
  // it, and focus goes back to the button.
  var menu = document.querySelector(".menu");
  if (menu) {
    var summary = menu.querySelector("summary");
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && menu.open) {
        menu.open = false;
        summary.focus();
      }
    });
    document.addEventListener("click", function (e) {
      if (menu.open && !menu.contains(e.target)) menu.open = false;
    });
  }

  // ---- Game footage ---------------------------------------------------------
  // Loops play muted, pause while off screen, and never start for someone who
  // has asked for reduced motion. The toggle is the WCAG 2.2.2 pause control.
  document.querySelectorAll("video[data-loop]").forEach(function (video) {
    var toggle = video.parentElement.querySelector(".play-toggle");
    var wanted = !still.matches;
    var visible = false;

    function sync() {
      if (wanted && visible) {
        var p = video.play();
        if (p && p.catch) p.catch(function () {});
      } else {
        video.pause();
      }
      if (toggle) {
        toggle.setAttribute("aria-pressed", wanted ? "false" : "true");
        toggle.textContent = wanted ? "Pause" : "Play";
      }
    }

    if (toggle) {
      toggle.hidden = false;
      toggle.addEventListener("click", function () {
        wanted = !wanted;
        sync();
      });
    }

    if ("IntersectionObserver" in window) {
      new IntersectionObserver(function (entries) {
        visible = entries[0].isIntersecting;
        sync();
      }, { threshold: 0.15 }).observe(video);
    } else {
      visible = true;
      sync();
    }
  });

  // ---- Reels ----------------------------------------------------------------
  // A set marked autoplay slides its cover along to the next piece every six
  // seconds, long enough to take each one in. Like the footage, it pauses off
  // screen, has a pause button (WCAG 2.2.2) and never starts for someone who
  // has asked for reduced motion; it also holds still while it is hovered or
  // has focus. The cover opens whichever piece is showing.
  document.querySelectorAll("[data-reel]").forEach(function (reel) {
    var track = reel.querySelector(".reel");
    var cover = reel.querySelector(".reel__cover");
    var toggle = reel.querySelector(".reel__toggle");
    var thumbs = reel.querySelectorAll(".piece__more [data-piece]");
    var wanted = !still.matches;
    var visible = false;
    var held = false;
    var timer = null;
    var at = 0;

    function go(i) {
      at = (i + thumbs.length) % thumbs.length;
      track.style.transform = "translateX(" + -100 * at + "%)";
      thumbs.forEach(function (t, k) {
        t.classList.toggle("is-showing", k === at);
      });
    }

    function sync() {
      clearInterval(timer);
      timer = wanted && visible && !held ? setInterval(function () { go(at + 1); }, 6000) : null;
      toggle.setAttribute("aria-pressed", wanted ? "false" : "true");
      toggle.textContent = wanted ? "Pause" : "Play";
    }

    toggle.hidden = false;
    toggle.addEventListener("click", function () {
      wanted = !wanted;
      sync();
    });
    // Held by the pictures, not by the button: pressing Play should play.
    function hold(e, on) {
      held = on && e.target !== toggle;
      sync();
    }
    [cover, reel.querySelector(".piece__more")].forEach(function (el) {
      el.addEventListener("mouseenter", function (e) { hold(e, true); });
      el.addEventListener("mouseleave", function (e) { hold(e, false); });
    });
    reel.addEventListener("focusin", function (e) { hold(e, true); });
    reel.addEventListener("focusout", function (e) {
      hold(e, reel.contains(e.relatedTarget) && e.relatedTarget !== toggle);
    });
    cover.addEventListener("click", function (e) {
      if (e.metaKey || e.ctrlKey || e.shiftKey || e.button !== 0) return;
      e.preventDefault();
      thumbs[at].click();
    });

    function seen(now) {
      if (now && !visible) {
        // Fetch the frames it is about to slide to before it gets there.
        track.querySelectorAll("img").forEach(function (img) { img.loading = "eager"; });
      }
      visible = now;
      sync();
    }
    if ("IntersectionObserver" in window) {
      new IntersectionObserver(function (entries) {
        seen(entries[0].isIntersecting);
      }, { threshold: 0.3 }).observe(reel);
    } else {
      seen(true);
    }
    go(0);
  });

  // ---- Work viewer ----------------------------------------------------------
  // A piece in a set (data-set) can step through the rest of its set, with
  // the buttons or the arrow keys.
  var pieces = document.querySelectorAll("[data-piece]");
  if (pieces.length && typeof HTMLDialogElement === "function") {
    var dialog = document.createElement("dialog");
    dialog.className = "viewer";
    dialog.setAttribute("aria-labelledby", "viewer-title");
    dialog.innerHTML =
      '<div class="viewer__media"></div>' +
      '<div class="viewer__text"><h2 id="viewer-title"></h2><p class="muted viewer__by"></p><p class="viewer__note"></p>' +
      '<div class="viewer__nav" hidden><button class="btn btn--small btn--cream" type="button" data-step="-1">Previous</button>' +
      '<span class="viewer__count" aria-live="polite"></span>' +
      '<button class="btn btn--small btn--cream" type="button" data-step="1">Next</button></div></div>' +
      '<button class="btn btn--small btn--cream viewer__close" type="button">Close</button>';
    document.body.appendChild(dialog);
    var media = dialog.querySelector(".viewer__media");
    var nav = dialog.querySelector(".viewer__nav");
    var set = [];
    var at = 0;

    function show(link) {
      var d = link.dataset;
      media.innerHTML = "";
      if (d.video) {
        var v = document.createElement("video");
        v.src = d.video;
        v.poster = link.href;
        v.controls = true;
        v.muted = true;
        v.loop = true;
        v.playsInline = true;
        if (!still.matches) v.autoplay = true;
        media.appendChild(v);
      } else {
        var img = document.createElement("img");
        img.src = link.href;
        img.alt = d.alt || "";
        media.appendChild(img);
      }
      dialog.querySelector("#viewer-title").textContent = d.title || "";
      dialog.querySelector(".viewer__by").textContent = d.by || "";
      dialog.querySelector(".viewer__note").textContent = d.note || "";
      nav.hidden = set.length < 2;
      dialog.querySelector(".viewer__count").textContent = set.length > 1 ? at + 1 + " of " + set.length : "";
    }

    function step(by) {
      if (set.length < 2) return;
      at = (at + by + set.length) % set.length;
      show(set[at]);
    }

    dialog.querySelector(".viewer__close").addEventListener("click", function () {
      dialog.close();
    });
    nav.addEventListener("click", function (e) {
      var button = e.target.closest("[data-step]");
      if (button) step(Number(button.getAttribute("data-step")));
    });
    dialog.addEventListener("keydown", function (e) {
      if (e.target.tagName === "VIDEO") return; // the arrows seek the clip there
      if (e.key === "ArrowRight") step(1);
      if (e.key === "ArrowLeft") step(-1);
    });
    dialog.addEventListener("click", function (e) {
      if (e.target === dialog) dialog.close();
    });
    dialog.addEventListener("close", function () {
      media.innerHTML = "";
    });

    pieces.forEach(function (link) {
      link.addEventListener("click", function (e) {
        if (e.metaKey || e.ctrlKey || e.shiftKey || e.button !== 0) return;
        e.preventDefault();
        var id = link.dataset.set;
        set = id
          ? Array.prototype.filter.call(pieces, function (p) {
              return p.dataset.set === id;
            })
          : [link];
        at = set.indexOf(link);
        show(link);
        dialog.showModal();
      });
    });
  }

  // ---- Contact form ---------------------------------------------------------
  var form = document.querySelector("form[data-contact]");
  if (form) {
    var about = form.querySelector("[name=about]");
    var fromUrl = new URLSearchParams(location.search).get("about");
    if (about && fromUrl) {
      var match = about.querySelector('option[value="' + fromUrl.replace(/[^a-z-]/g, "") + '"]');
      if (match) about.value = match.value;
    }

    var codevOnly = form.querySelectorAll("[data-codev]");
    function showCodev() {
      var on = about && about.value === "codev";
      codevOnly.forEach(function (el) {
        el.hidden = !on;
      });
    }
    if (about) about.addEventListener("change", showCodev);
    showCodev();

    // "artstation.com/me" is what people type; the inbox wants a link that
    // opens when clicked.
    var link = form.querySelector("[name=link]");
    function tidyLink() {
      var v = link.value.trim();
      link.value = v && !/^[a-z][a-z0-9+.-]*:/i.test(v) ? "https://" + v : v;
    }

    var status = form.querySelector(".form-status");
    form.addEventListener("submit", function (e) {
      if (link) tidyLink();
      if (!window.fetch || !window.FormData) return;
      e.preventDefault();
      var button = form.querySelector("[type=submit]");
      button.disabled = true;
      status.className = "form-status";
      status.textContent = "Sending...";
      fetch(form.action, {
        method: "POST",
        body: new FormData(form),
        headers: { Accept: "application/json" }
      })
        .then(function (r) {
          if (!r.ok) throw new Error(r.status);
          form.reset();
          showCodev();
          status.textContent = "Sent. Thank you. A real person will read it and reply to the address you gave.";
        })
        .catch(function () {
          status.className = "form-status is-error";
          status.textContent = "That did not send. Please try again, or email contact@shiverbugstudios.com instead.";
        })
        .then(function () {
          button.disabled = false;
          status.focus();
        });
    });
  }

  // ---- Old profile links ----------------------------------------------------
  // team-member.html?p=lewis used to be how a profile was addressed.
  var legacy = document.querySelector("[data-legacy-people]");
  if (legacy) {
    var map = JSON.parse(legacy.getAttribute("data-legacy-people"));
    var p = new URLSearchParams(location.search).get("p");
    location.replace(p && map[p] ? "/team/" + map[p] : "/team/");
  }
})();

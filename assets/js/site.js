// Shiverbug Studios. Everything here is an improvement on a page that already
// works without it: the footage shows its poster, work links open the full
// image, and the forms post normally.
(function () {
  "use strict";

  var still = window.matchMedia("(prefers-reduced-motion: reduce)");

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

  // ---- Work viewer ----------------------------------------------------------
  var pieces = document.querySelectorAll("[data-piece]");
  if (pieces.length && typeof HTMLDialogElement === "function") {
    var dialog = document.createElement("dialog");
    dialog.className = "viewer";
    dialog.setAttribute("aria-labelledby", "viewer-title");
    dialog.innerHTML =
      '<div class="viewer__media"></div>' +
      '<div class="viewer__text"><h2 id="viewer-title"></h2><p class="muted viewer__by"></p><p class="viewer__note"></p></div>' +
      '<button class="btn btn--small btn--cream viewer__close" type="button">Close</button>';
    document.body.appendChild(dialog);
    var media = dialog.querySelector(".viewer__media");

    dialog.querySelector(".viewer__close").addEventListener("click", function () {
      dialog.close();
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

    var status = form.querySelector(".form-status");
    form.addEventListener("submit", function (e) {
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

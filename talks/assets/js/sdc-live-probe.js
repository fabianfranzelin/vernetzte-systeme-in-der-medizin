/*
 * sdc-live-probe.js
 *
 * Runtime reachability probe for the SDC demo talk.
 *
 * Any element with a `data-sdc-live="<url>"` attribute is treated as a
 * fallback container that holds:
 *   - one <iframe data-live-iframe> (hidden by default), and
 *   - one <img data-fallback-img> (visible by default).
 *
 * On slide activation (or DOMContentLoaded outside reveal.js), we perform a
 * short, cache-busted `fetch(url, { mode: "no-cors" })` with a 1.5 s timeout.
 * On success, the iframe is loaded and shown, the image is hidden. On
 * failure/timeout, the static image remains visible.
 *
 * Probe results are cached per URL so multiple containers pointing at the
 * same origin only pay the round-trip once.
 */
(function () {
  if (window.__sdcLiveProbe) return;
  window.__sdcLiveProbe = true;

  var timeoutMs = 1500;
  var cache = {};

  function probe(url, cb) {
    if (cache[url] !== undefined) {
      cb(cache[url]);
      return;
    }
    var done = false;
    var t = setTimeout(function () {
      if (!done) {
        done = true;
        cache[url] = false;
        cb(false);
      }
    }, timeoutMs);
    fetch(url, { mode: "no-cors", cache: "no-store" })
      .then(function () {
        if (!done) {
          done = true;
          clearTimeout(t);
          cache[url] = true;
          cb(true);
        }
      })
      .catch(function () {
        if (!done) {
          done = true;
          clearTimeout(t);
          cache[url] = false;
          cb(false);
        }
      });
  }

  function activate(container) {
    if (container.dataset.probed === "1") return;
    container.dataset.probed = "1";
    var url = container.getAttribute("data-sdc-live");
    var iframe = container.querySelector("iframe[data-live-iframe]");
    var img = container.querySelector("img[data-fallback-img]");
    if (!url || !iframe || !img) return;
    probe(url, function (ok) {
      if (ok) {
        iframe.src = url;
        iframe.style.display = "block";
        img.style.display = "none";
      } else {
        iframe.style.display = "none";
        img.style.display = "block";
      }
    });
  }

  function activateAll() {
    document.querySelectorAll("[data-sdc-live]").forEach(activate);
  }

  if (window.Reveal && typeof window.Reveal.on === "function") {
    window.Reveal.on("ready", activateAll);
    window.Reveal.on("slidechanged", activateAll);
  } else {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", activateAll);
    } else {
      activateAll();
    }
  }
})();

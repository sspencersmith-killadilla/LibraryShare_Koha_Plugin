(function () {
  "use strict";
  var launchUrl = "/api/v1/contrib/libraryshare/static/app.html?v=0.2.8";
  if (document.getElementById("libraryshare-opac-link")) return;
  var link = document.createElement("a");
  link.id = "libraryshare-opac-link";
  link.href = launchUrl;
  link.textContent = "LibraryShare";
  link.setAttribute("aria-label", "Open LibraryShare community lending");
  link.style.cssText = [
    "position:fixed", "right:18px", "bottom:18px", "z-index:99999",
    "padding:12px 18px", "border-radius:999px", "background:#1c4d42",
    "color:#fff", "font:600 14px/1.2 system-ui,sans-serif",
    "text-decoration:none", "box-shadow:0 8px 24px #17372d33"
  ].join(";");
  document.body.appendChild(link);
  // Fixed same-origin return only; never accept a user-supplied redirect URL.
  try {
    var started=Number(sessionStorage.getItem("libraryshare-login-return"));
    if(started && Date.now()-started < 15*60*1000) {
      fetch("/api/v1/contrib/libraryshare/bootstrap",{credentials:"same-origin",cache:"no-store"})
        .then(function(r){if(!r.ok)throw new Error("Session unavailable");return r.json();})
        .then(function(data){if(data.signed_in){sessionStorage.removeItem("libraryshare-login-return");location.assign(launchUrl);}})
        .catch(function(){ /* Keep the visible public link for manual return. */ });
    } else sessionStorage.removeItem("libraryshare-login-return");
  } catch (_) { /* Storage may be disabled; the public link still works. */ }
})();

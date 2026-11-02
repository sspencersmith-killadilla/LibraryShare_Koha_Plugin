(function () {
  "use strict";

  var API = "/api/v1/contrib/libraryshare";
  var state = { bootstrap: null, listings: [], wanted: [], dashboard: null, view: "home" };
  var root = document.getElementById("libraryshare-app");
  var notice = document.getElementById("notice");
  var branches = document.getElementById("branch-select");

  function escapeHtml(value) {
    return String(value == null ? "" : value).replace(/[&<>"']/g, function (char) {
      return ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char];
    });
  }

  async function api(path, options) {
    if (options && options.method === "POST" && /^\/(listings|requests|wanted|reviews|kudos)(\/|$)/.test(path)) {
      if (!state.bootstrap || !state.bootstrap.signed_in) { setView("login"); throw new Error("Sign in to Koha to continue."); }
      await window.LSExt.ensureAgreements();
    }
    var init = Object.assign({ credentials: "same-origin", cache: "no-store" }, options || {});
    init.headers = Object.assign({ Accept: "application/json" }, init.headers || {});
    if (init.body && typeof init.body !== "string") {
      init.headers["Content-Type"] = "application/json";
      init.body = JSON.stringify(init.body);
    }
    var controller=new AbortController(), timeout=window.setTimeout(function(){controller.abort();},20000), response;
    init.signal=controller.signal;
    var data = {};
    try {
      response=await fetch(API + path, init);
      try { data = await response.json(); } catch (_) { if(response.ok)throw new Error("Koha returned an unreadable response. Check the plugin API installation."); }
    } catch(error) {
      if(error.name==="AbortError")throw new Error("Koha took too long to respond. Retry, or ask staff to check the plugin API.");
      throw error;
    } finally {window.clearTimeout(timeout);}
    if (!response.ok) {
      if(response.status===401 && state.bootstrap) {
        state.bootstrap.signed_in=0;state.bootstrap.patron=null;state.dashboard=null;
        if(window.LSExt.config)window.LSExt.config.is_admin=0;
        document.getElementById("session-label").textContent="Session expired — sign in again";
        setView("login");
      }
      var failure = new Error(data.error || ("Request failed (" + response.status + ")"));
      failure.status = response.status;
      throw failure;
    }
    return data;
  }

  function showNotice(message, isError) {
    notice.textContent = message;
    notice.classList.toggle("error", Boolean(isError));
    notice.hidden = false;
    window.clearTimeout(showNotice.timer);
    showNotice.timer = window.setTimeout(function () { notice.hidden = true; }, 5200);
  }

  function setView(name) {
    if(state.view==="admin" && name!=="admin" && window.LSStaff)window.LSStaff.cancelPreview();
    if (["add", "dashboard", "profile", "admin"].indexOf(name) >= 0 && (!state.bootstrap || !state.bootstrap.signed_in)) name = "login";
    if (name === "admin" && !(window.LSExt.config && window.LSExt.config.is_admin)) name = "login";
    state.view = name;
    document.querySelectorAll(".view").forEach(function (view) {
      view.hidden = view.id !== "view-" + name;
    });
    document.querySelectorAll(".tab").forEach(function (tab) {
      tab.classList.toggle("active", tab.dataset.view === name);
    });
    if (name === "home") loadListings();
    if (name === "wanted") loadWanted();
    if (name === "dashboard") loadDashboard();
    if (name === "community") loadCommunity();
    if (name === "profile" || name === "documents" || name === "admin") window.LSExt.view(name);
    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  function currentBorrowernumber() {
    return state.bootstrap && state.bootstrap.patron
      ? Number(state.bootstrap.patron.borrowernumber)
      : 0;
  }

  function renderListingCard(item) {
    var owner = [item.firstname, item.surname].filter(Boolean).join(" ") || "Library member";
    var isOwn = Boolean(Number(item.is_mine));
    return '<article class="listing-card">' +
      (window.LSExt.image(item.photo_url) ? '<img class="cover" loading="lazy" src="' + escapeHtml(window.LSExt.image(item.photo_url)) + '" alt="' + escapeHtml(item.title) + '">' : '') +
      '<div class="card-top"><span class="category">' + escapeHtml(item.category || "Shared item") + '</span><span class="condition">' + escapeHtml(item.item_condition || "good") + ' condition</span></div>' +
      '<h3><button class="link-button card-title" data-action="detail" data-id="' + Number(item.id) + '">' + escapeHtml(item.title) + '</button></h3>' +
      (item.author ? '<p class="byline">' + escapeHtml(item.author) + '</p>' : '') +
      '<p class="description">' + escapeHtml(item.description || "Available to borrow through your library community.") + '</p>' +
      '<p class="byline">Estimated item value: ' + window.LSExt.itemValue(item.estimated_value) + ' · No borrowing fee</p>' +
      '<div class="listing-foot"><span class="owner">Shared by ' + (item.owner_borrowernumber ? '<button class="link-button" data-action="profile" data-id="' + Number(item.owner_borrowernumber) + '">' + escapeHtml(owner) + '</button>' : escapeHtml(owner)) + '</span>' +
      (state.bootstrap && state.bootstrap.signed_in && !isOwn
        ? '<button class="request-button" data-action="request" data-id="' + Number(item.id) + '">Request item</button>'
        : isOwn ? '<span class="owner">Your item</span>' : '<a class="request-button" data-koha-link="1" href="' + escapeHtml(window.LSExt.kohaUrl()) + '">Sign in to request</a>') +
      '</div></article>';
  }

  async function loadListings(query) {
    var container = document.getElementById("listing-grid");
    container.innerHTML = '<div class="loading">Loading listings…</div>';
    document.getElementById("browse-results-count").textContent="";
    try {
      var filters = new URLSearchParams(new FormData(document.getElementById("facet-form")));
      if (filters.get("available_from") && filters.get("available_to") && filters.get("available_to") < filters.get("available_from")) throw new Error("The availability end date must be on or after its start date.");
      filters.set("q", query == null ? document.getElementById("search-query").value.trim() : query);
      var result = await api("/listings?" + filters.toString());
      state.listings = result.listings || [];
      if (result.total_available != null) document.getElementById("community-count").textContent=String(result.total_available);
      document.getElementById("browse-results-count").textContent =
        state.listings.length + " matching items shown" + (state.listings.length===100 ? " (up to 100 per search)" : "");
      container.innerHTML = state.listings.length
        ? state.listings.map(renderListingCard).join("")
        : '<div class="empty">No available items match that search yet. Try another term or post a wanted item.</div>';
    } catch (error) {
      container.innerHTML = window.LSExt.error(error, "retry-listings");
    }
  }

  async function loadWanted() {
    var container = document.getElementById("wanted-list");
    container.innerHTML = '<div class="loading">Loading wanted items…</div>';
    try {
      var result = await api("/wanted?status=" + encodeURIComponent(window.LSExt.wantedStatus || "open"));
      state.wanted = result.wanted || [];
      container.innerHTML = state.wanted.length ? state.wanted.map(function (item) {
        return '<article class="wanted-row"><div><h3>' + escapeHtml(item.title) + '</h3><p>' +
          escapeHtml(item.category || "Any category") + (item.description ? " · " + escapeHtml(item.description) : "") +
          '</p><p>Posted by ' + escapeHtml([item.firstname, item.surname].filter(Boolean).join(" ") || "Library member") + '</p></div>' +
          '<div class="wanted-actions"><span class="status-pill">' + Number(item.interest_count || 0) + ' interested</span>' +
          (Number(item.is_mine)
            ? window.LSExt.wantedControls(item)
            : state.bootstrap && state.bootstrap.signed_in
              ? '<button class="button button-light" data-action="wanted-interest" data-id="' + Number(item.id) + '" data-interested="' + (Number(item.my_interest) ? "0" : "1") + '">' + (Number(item.my_interest) ? "Remove interest" : "Follow this wish") + '</button><button class="button button-dark" data-action="offer-wanted" data-id="' + Number(item.id) + '">I can lend this</button>'
              : '<a class="button button-light" data-koha-link="1" href="' + escapeHtml(window.LSExt.kohaUrl()) + '">Sign in to respond</a>') +
          '</div></article>';
      }).join("") : '<div class="empty">No open wanted items. Add the first request for your community.</div>';
      window.LSExt.loadMatches();
    } catch (error) {
      container.innerHTML = window.LSExt.error(error, "retry-wanted");
    }
  }

  function requestActions(request, isOwner) {
    var actions = [];
    if (request.status === "pending" && isOwner) {
      actions.push('<button class="button button-dark" data-action="accept" data-id="' + Number(request.id) + '">Accept</button>');
      actions.push('<button class="button button-light" data-action="decline" data-id="' + Number(request.id) + '">Decline</button>');
    } else if (request.status === "accepted" && isOwner) {
      actions.push('<button class="button button-dark" data-action="pickup-form" data-id="' + Number(request.id) + '" data-listing="' + Number(request.listing_id) + '" data-loan="' + Number(request.listing_default_loan_days || 14) + '">Set pickup time</button>');
    } else if (request.status === "approved" && isOwner) {
      actions.push('<button class="button button-light" data-action="return" data-id="' + Number(request.id) + '">Mark returned</button>');
    } else if (request.status === "returned") {
      actions.push('<button class="button button-light" data-action="review" data-id="' + Number(request.id) + '">Leave review</button>');
      if (!isOwner) actions.push('<button class="button button-light" data-action="kudos" data-id="' + Number(request.id) + '">Thank lender</button>');
    } else if (request.status === "pending" && !isOwner) {
      actions.push('<span class="owner">Waiting for lender</span>');
    } else if (request.status === "approved") {
      actions.push('<span class="owner">Koha checkout active</span>');
    }
    actions.push('<button class="button button-light" data-action="messages" data-id="' + Number(request.id) + '">Messages</button>');
    actions.push(window.LSExt.requestControls(request, isOwner));
    return actions.join("");
  }

  async function loadDashboard() {
    var requests = document.getElementById("request-list");
    requests.innerHTML = '<div class="loading">Loading your activity…</div>';
    try {
      var data = await api("/dashboard");
      state.dashboard = data;
      var stats = data.stats || {};
      document.getElementById("dashboard-stats").innerHTML = [
        ["Shared", stats.distinct_items_lent || 0],
        ["Loans as lender", stats.loans_as_lender || 0],
        ["Loans as borrower", stats.loans_as_borrower || 0],
        ["Share credits", stats.share_credits || 0]
      ].map(function (pair) {
        return '<div class="stat"><strong>' + escapeHtml(pair[1]) + '</strong><span>' + escapeHtml(pair[0]) + '</span></div>';
      }).join("");

      requests.innerHTML = data.requests && data.requests.length ? data.requests.map(function (request) {
        var isOwner = Number(request.owner_borrowernumber) === currentBorrowernumber();
        var other = isOwner
          ? [request.borrower_firstname, request.borrower_surname].filter(Boolean).join(" ")
          : [request.lender_firstname, request.lender_surname].filter(Boolean).join(" ");
        var label = isOwner ? "Borrower" : "Lender";
        return '<article class="request-row"><div><h3>' + escapeHtml(request.title) + '</h3><p>' + label + ' ' + escapeHtml(other || "Library member") +
          ' · ' + escapeHtml(request.created_at || "") + '</p><span class="status-pill">' + escapeHtml(request.status) + '</span>' +
          (request.pickup_starts_at ? '<p>Pickup: ' + escapeHtml(request.pickup_starts_at) + (request.pickup_location ? ' · ' + escapeHtml(request.pickup_location) : '') + '</p>' : '') +
          (request.due_date ? '<p>Due ' + escapeHtml(request.due_date) + '</p>' : '') +
          (request.borrower_message ? '<p class="body-copy">Borrower note: ' + escapeHtml(request.borrower_message) + '</p>' : '') +
          (request.proposed_start || request.proposed_end ? '<p>Requested dates: ' + escapeHtml(request.proposed_start || "Flexible start") + ' to ' + escapeHtml(request.proposed_end || "Flexible end") + ' · subject to lender confirmation</p>' : '') +
          (request.borrower_priority ? '<span class="status-pill">Queue priority</span>' : '') +
          (request.borrower_fast_track ? '<span class="status-pill">Reliable borrower / fast track</span>' : '') +
          '<div id="pickup-form-' + Number(request.id) + '"></div><div id="messages-' + Number(request.id) + '"></div></div><div class="request-actions">' +
          requestActions(request, isOwner) + '</div></article>';
      }).join("") : '<div class="empty">You do not have any lending requests yet.</div>';

      var myListings = data.listings || [];
      document.getElementById("my-listings").innerHTML = myListings.length ? myListings.map(function (item) {
        return '<article class="my-listing-row"><div><h3>' + escapeHtml(item.title) + '</h3><p>' +
          escapeHtml(item.category) + ' · ' + escapeHtml(item.status) + '</p></div><div class="wanted-actions">' +
          (item.status === "active" || item.status === "paused"
            ? '<button class="button button-light" data-action="edit-listing" data-id="' + Number(item.id) + '">Edit</button>' +
              '<button class="button button-light" data-action="listing-status" data-id="' + Number(item.id) + '" data-status="' + (item.status === "active" ? "paused" : "active") + '">' + (item.status === "active" ? "Pause" : "Resume") + '</button>' +
              '<button class="button button-light" data-action="listing-status" data-id="' + Number(item.id) + '" data-status="removed">Remove</button>'
            : '<span class="status-pill">' + escapeHtml(item.status) + '</span>') +
          '</div></article>';
      }).join("") : '<div class="empty">Your listings will appear here.</div>';
      var myWanted = data.wanted || [];
      document.getElementById("my-wanted").innerHTML = myWanted.length ? myWanted.map(function (item) {
        return '<article class="wanted-row"><div><h3>' + escapeHtml(item.title) + '</h3><p>' + escapeHtml(item.category || "Any category") + '</p></div><div class="wanted-actions"><span class="status-pill">' + escapeHtml(item.status) + '</span>' + window.LSExt.wantedControls(item) + '</div></article>';
      }).join("") : '<div class="empty">Your wanted posts will appear here.</div>';
      await loadNotifications();
    } catch (error) {
      requests.innerHTML = window.LSExt.error(error, "retry-dashboard");
      if (/sign in|session/i.test(error.message)) setView("login");
    }
  }

  async function loadNotifications() {
    var container = document.getElementById("notifications-list");
    try {
      var data = await api("/notifications");
      var rows = data.notifications || [];
      state.notifications = rows;
      container.innerHTML = rows.length ? rows.map(function (item) {
        return '<article class="wanted-row ' + (item.read_at ? "is-read" : "is-unread") + '"><div><h3>' +
          escapeHtml(item.title) + '</h3><p>' + escapeHtml(item.body || "") + ' · ' + escapeHtml(item.created_at || "") +
          '</p></div>' + (!item.read_at ? '<button class="button button-light" data-action="notification-read" data-id="' + Number(item.id) + '">Mark read</button>' : '<span class="status-pill">Read</span>') +
          '<button class="button button-light" data-action="dismiss-notification" data-id="' + Number(item.id) + '">Dismiss</button></article>';
      }).join("") : '<div class="empty">You have no notifications.</div>';
    } catch (error) {
      container.innerHTML = '<div class="empty">' + escapeHtml(error.message) + '</div>';
    }
  }

  async function loadCommunity() {
    var categories = document.getElementById("category-list");
    var leaderboard = document.getElementById("leaderboard-list");
    var challenges = document.getElementById("challenge-list");
    try {
      var results = await Promise.all([
        api("/community"), api("/leaderboard"), api("/challenges"), api("/impact")
      ]);
      var community = results[0], leaders = results[1].leaderboard || [];
      var activeChallenges = results[2].challenges || [];
      var own = results[3].patron || {};
      var totals = community.totals || {};
      document.getElementById("community-stats").innerHTML = [
        ["Items available", totals.listings || 0],
        ["Loans tracked", totals.loans || 0],
        ["Active lenders", totals.active_lenders || 0],
        ["Your level", own.level || "—"]
      ].map(function (pair) {
        return '<div class="stat"><strong>' + escapeHtml(pair[1]) + '</strong><span>' + escapeHtml(pair[0]) + '</span></div>';
      }).join("");
      categories.innerHTML = community.categories && community.categories.length
        ? community.categories.map(function (row) {
          return '<article class="wanted-row"><div><h3>' + escapeHtml(row.category) + '</h3></div><span class="status-pill">' + Number(row.item_count) + ' items</span></article>';
        }).join("")
        : '<div class="empty">Category activity will appear as items are listed.</div>';
      leaderboard.innerHTML = leaders.length
        ? leaders.slice(0, 10).map(function (row, index) {
          return '<article class="wanted-row"><div><h3>' + (index + 1) + '. ' +
            escapeHtml([row.firstname, row.surname].filter(Boolean).join(" ") || "Library member") +
            '</h3><p>' + Number(row.loans_as_lender || 0) + ' completed loans · level ' + Number(row.level || 1) +
            '</p></div><span class="status-pill">' + Number(row.share_credits || 0) + ' credits</span></article>';
        }).join("")
        : '<div class="empty">Lender recognition will appear after completed loans.</div>';
      challenges.innerHTML = activeChallenges.length
        ? activeChallenges.map(function (row) {
          var progress = Number(row.progress || 0), goal = Number(row.goal || 1);
          return '<article class="wanted-row"><div><h3>' + escapeHtml(row.title) + '</h3><p>' +
            escapeHtml(row.description || "") + ' · ' + escapeHtml(row.end_date || "") +
            '</p></div><span class="status-pill">' + progress + ' / ' + goal + '</span></article>';
        }).join("")
        : '<div class="empty">There are no active challenges right now.</div>';
      document.getElementById("personal-impact").innerHTML = state.bootstrap && state.bootstrap.signed_in
        ? '<p class="eyebrow">Your contribution</p><p class="impact-copy"><strong>' + Number(own.loans_as_lender || 0) +
          '</strong> lending loans · <strong>$' + Number(own.est_value_saved || 0).toFixed(2) +
          '</strong> estimated value saved</p><p class="form-hint">50% of each item’s current estimated value per completed loan. Items without a value are excluded. Value edits recalculate past savings.</p>'
        : '<p class="muted">Sign in to Koha to see your personal impact.</p>';
      window.LSExt.loadImpact();
    } catch (error) {
      categories.innerHTML = window.LSExt.error(error, "retry-community");
    }
  }

  function formObject(form) {
    return Object.fromEntries(new FormData(form).entries());
  }

  async function onClick(event) {
    var actionButton = event.target.closest("[data-action]");
    if (actionButton) {
      event.preventDefault();
      if (actionButton.disabled) return;
      actionButton.disabled = true;
      var action = actionButton.dataset.action;
      var id = actionButton.dataset.id;
      try {
        if(action==="reload-app"){location.reload();return;}
        if (await window.LSExt.action(action, actionButton)) return;
        if (action === "request") {
          await api("/requests", { method: "POST", body: { listing_id: id } });
          showNotice("Your request was sent to the lender.");
          if (state.view === "dashboard") loadDashboard();
        } else if (action === "accept" || action === "decline" || action === "return") {
          await api("/requests/" + encodeURIComponent(id) + "/" + action, { method: "POST", body: {} });
          showNotice(action === "return" ? "The item was checked in through Koha." : "The request was updated.");
          loadDashboard();
        } else if (action === "messages") {
          var panel = document.getElementById("messages-" + id);
          if (!panel) return;
          if (panel.dataset.open === "1") { panel.innerHTML = ""; panel.dataset.open = "0"; return; }
          panel.dataset.open = "1";
          var data = await api("/messages?request_id=" + encodeURIComponent(id));
          panel.innerHTML = '<div class="message-thread">' + (data.messages || []).map(function (message) {
            var name = [message.firstname, message.surname].filter(Boolean).join(" ") || "Library member";
            return '<p><strong>' + escapeHtml(name) + '</strong> · ' + escapeHtml(message.created_at || "") +
              '<br>' + escapeHtml(message.message) + '</p>';
          }).join("") + '<form class="message-form" data-request="' + Number(id) + '">' +
            '<label class="sr-only" for="message-' + Number(id) + '">Write a message</label>' +
            '<input id="message-' + Number(id) + '" name="message" maxlength="2000" required placeholder="Write a message">' +
            '<button class="button button-light">Send</button></form></div>';
        } else if (action === "notification-read") {
          await api("/notifications/" + encodeURIComponent(id) + "/read", { method: "POST" });
          await loadNotifications();
        } else if (action === "listing-status") {
          var nextStatus = actionButton.dataset.status;
          if (nextStatus === "removed" && !window.confirm("Remove this item from LibraryShare? Its Koha catalog record will remain.")) return;
          await api("/listings/" + encodeURIComponent(id), { method: "POST", body: { status: nextStatus } });
          showNotice("Listing updated.");
          await loadDashboard();
        } else if (action === "wanted-interest") {
          await api("/wanted/" + encodeURIComponent(id) + "/interest", { method: "POST", body: { interested: actionButton.dataset.interested === "1" } });
          await loadWanted();
        }
      } catch (error) {
        showNotice(error.message, true);
      } finally { actionButton.disabled = false; }
      return;
    }
    var tab = event.target.closest("[data-view]");
    if (tab) {
      event.preventDefault();
      if (tab.dataset.view === "profile") window.LSExt.resetProfile();
      setView(tab.dataset.view);
    }
  }

  async function onSubmit(event) {
    var form = event.target;
    event.preventDefault();
    if (form.dataset.busy === "1") return;
    form.dataset.busy = "1";
    var submitButton = form.querySelector('button:not([type="button"])');
    if (submitButton) submitButton.disabled = true;
    try {
      if (form.id === "search-form") {
        await loadListings(document.getElementById("search-query").value.trim());
      } else if (await window.LSExt.submit(form)) {
        return;
      } else if (form.id === "listing-form") {
        var listing = formObject(form);
        listing.default_loan_days = Number(listing.default_loan_days);
        delete listing.photos;
        var result = await api("/listings", { method: "POST", body: listing });
        await window.LSExt.afterListingCreated(result, form);
        form.reset();
        form.querySelector('[name="default_loan_days"]').value = String(state.bootstrap.default_loan_days || 14);
        showNotice("Your listing and Koha item record were created.");
        setView("home");
      } else if (form.id === "wanted-form") {
        await api("/wanted", { method: "POST", body: formObject(form) });
        form.reset();
        showNotice("Your wanted item was posted.");
        await loadWanted();
      } else if (form.matches(".message-form")) {
        await api("/messages", {
          method: "POST",
          body: { request_id: Number(form.dataset.request), message: formObject(form).message }
        });
        showNotice("Your message was sent.");
        var panel = document.getElementById("messages-" + form.dataset.request);
        if (panel) panel.dataset.open = "0";
        await loadDashboard();
      }
    } catch (error) {
      showNotice(error.message, true);
    } finally { form.dataset.busy = "0"; if (submitButton) submitButton.disabled = false; }
  }

  async function init() {
    root.addEventListener("click", onClick);
    root.addEventListener("submit", onSubmit);
    document.getElementById("refresh-dashboard").addEventListener("click", loadDashboard);
    try {
      if(!window.LSExt || !window.LSExt.attach)throw new Error("The LibraryShare extended.js asset did not load. Check that plugin static assets are installed and accessible.");
      window.LSExt.attach({api:api,state:state,escape:escapeHtml,notice:showNotice,setView:setView,loadListings:loadListings,loadWanted:loadWanted,loadDashboard:loadDashboard,loadNotifications:loadNotifications,loadCommunity:loadCommunity,card:renderListingCard,form:formObject,patronId:currentBorrowernumber});
      state.bootstrap = await api("/bootstrap");
      var nav=state.bootstrap.navigation || {};
      ["koha-account","koha-sign-in"].forEach(function(id) {
        var link=document.getElementById(id);
        if(nav.account_url) {
          link.href=nav.account_url; link.hidden=false;
          link.textContent=nav.context==="public" ? "My Koha account / sign in" : "Staff Koha sign-in";
          link.target="_top";
          if(id==="koha-sign-in" && nav.context==="public") link.onclick=function(){
            try { sessionStorage.setItem("libraryshare-login-return",String(Date.now())); } catch (_) {}
          };
        }
      });
      document.getElementById("login-guidance").textContent=nav.configuration_error ||
        (nav.context==="public" ? "Sign in using your library card account. Return using the LibraryShare link if automatic return is unavailable." :
          "This is the staff console. Patrons should use LibraryShare on the public catalog.");
      if(nav.context==="staff" && nav.public_url) {
        var publicLink=document.createElement("a");publicLink.href=nav.public_url;publicLink.target="_top";
        publicLink.textContent=" Open public LibraryShare";document.getElementById("login-guidance").appendChild(publicLink);
      }
      var patron = state.bootstrap.patron;
      document.getElementById("session-label").textContent = patron
        ? "Signed in as " + [patron.firstname, patron.surname].filter(Boolean).join(" ")
        : "Not signed in";
      if (!patron) document.getElementById("session-label").classList.add("muted");
      document.getElementById("community-count").textContent = String((state.bootstrap.community || {}).listings || 0);
      document.querySelector('#listing-form [name="default_loan_days"]').value = String(state.bootstrap.default_loan_days || 14);
      var branchList = state.bootstrap.branches || [];
      branches.innerHTML = branchList.map(function (branch) {
        return '<option value="' + escapeHtml(branch.branchcode) + '">' + escapeHtml(branch.branchname) + '</option>';
      }).join("");
      if (!branchList.length) branches.innerHTML = '<option value="">Use my Koha home library</option>';
      await window.LSExt.init();
      var initial = location.hash.slice(1);
      setView(["home","wanted","dashboard","community","add","profile","documents","admin"].indexOf(initial) >= 0 ? initial : "home");
      if(window.LSStartup)window.LSStartup.ready();
    } catch (error) {
      if(window.LSStartup)window.LSStartup.fail("The Koha session/configuration request failed.");
      document.getElementById("session-label").textContent = "Koha connection unavailable";
      document.getElementById("listing-grid").innerHTML =
        '<div class="empty" role="alert">LibraryShare could not start. ' + escapeHtml(error.message) + ' Ask your library administrator to check the plugin installation. <button type="button" class="button button-light" data-action="reload-app">Reload LibraryShare</button></div>';
      showNotice(error.message, true);
    }
  }

  init();
})();

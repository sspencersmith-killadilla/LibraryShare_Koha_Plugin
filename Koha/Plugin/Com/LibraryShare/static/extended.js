(function () {
  "use strict";
  var B, dialog, lastFocus, profileId = null, profileData = null, suspendedDialog = null, brandingDefaults = null;
  var X = window.LSExt = {config: null, wantedStatus: "open"};
  X.itemValue = function(value) { return value == null || value === "" ? "Not set" : "$" + Number(value).toFixed(2); };
  X.attach = function (context) { B = context; X.context = B; };
  function e(value) { return B.escape(value); }
  function num(value) { return Number(value || 0); }
  async function ext(area, data) {
    if (area === "fulfil" && data && data.listing_id) await X.ensureAgreements();
    return B.api("/extended/" + area, data === undefined ? undefined : {method:"POST",body:data});
  }
  X.ext = ext;
  function button(label, action, id, extra) {
    return '<button type="button" class="button button-light" data-action="' + e(action) + '"' + (id == null ? '' : ' data-id="' + e(id) + '"') + (extra || '') + '>' + e(label) + '</button>';
  }
  X.button = button;
  function empty(message) { return '<div class="empty">' + e(message) + '</div>'; }
  X.empty = empty;
  X.error = function (error, action) { return '<div class="empty" role="alert">' + e(error.message || error) + (action ? button("Try again",action) : '') + '</div>'; };
  X.image = function (url) {
    if (!url) return "";
    try { var parsed = new URL(url, location.href); return parsed.origin === location.origin && /^https?:$/.test(parsed.protocol) ? parsed.href : ""; } catch (_) { return ""; }
  };
  X.safeBrandUrl = function (value) {
    if (!value || !String(value).trim()) return "";
    try {
      var url = new URL(String(value).trim(),location.href);
      return url.protocol === "https:" || (url.origin === location.origin && /^https?:$/.test(url.protocol)) ? url.href : "";
    } catch (_) { return ""; }
  };
  X.kohaUrl = function () { return X.safeBrandUrl(X.config && X.config.branding && X.config.branding.koha_public_url) || "/cgi-bin/koha/opac-user.pl"; };
  X.brandPresets = {
    sunny:{primary_color:"#b64232",accent_color:"#b95727",background_color:"#fff7e6",foreground_color:"#302d38",mint:"#fbe6cf",paper:"#fffdf7",line:"#e9d9c7"},
    ocean:{primary_color:"#206078",accent_color:"#ac4b39",background_color:"#edf7fa",foreground_color:"#263b47",mint:"#d9edf2",paper:"#f8fcfd",line:"#c8dfe6"},
    forest:{primary_color:"#355f4b",accent_color:"#9d4f35",background_color:"#f2f5e8",foreground_color:"#303d30",mint:"#e1e9cf",paper:"#fbfcf5",line:"#d3ddc5"}
  };
  X.brandValues = function (branding) {
    var source=branding || {}, theme=X.brandPresets[source.theme_preset] ? source.theme_preset : "sunny";
    var values=Object.assign({font_style:"friendly",corner_style:"rounded",density:"comfortable"},source,{theme_preset:theme});
    ["primary_color","accent_color","background_color","foreground_color"].forEach(function(key){if(!/^#[a-f0-9]{6}$/i.test(values[key] || ""))values[key]=X.brandPresets[theme][key];});
    if(["friendly","classic","system"].indexOf(values.font_style)<0)values.font_style="friendly";
    if(["rounded","square"].indexOf(values.corner_style)<0)values.corner_style="rounded";
    if(["comfortable","compact"].indexOf(values.density)<0)values.density="comfortable";
    return values;
  };
  X.applyBranding = function (branding, preview) {
    branding = branding || {};
    var visual=X.brandValues(branding), preset=X.brandPresets[visual.theme_preset] || X.brandPresets.sunny, style=document.documentElement.style;
    style.setProperty("--ls-body",visual.font_style==="classic" ? 'Georgia,serif' : visual.font_style==="system" ? 'system-ui,sans-serif' : '"Trebuchet MS",ui-sans-serif,system-ui,sans-serif');
    style.setProperty("--ls-heading",visual.font_style==="friendly" ? 'Georgia,serif' : visual.font_style==="classic" ? 'Georgia,serif' : 'system-ui,sans-serif');
    style.setProperty("--ls-radius",visual.corner_style==="square" ? "2px" : "14px");
    style.setProperty("--ls-space",visual.density==="compact" ? "12px" : "20px");
    ["mint","paper","line"].forEach(function(key){style.setProperty("--"+key,preset[key]);});
    style.setProperty("--muted","var(--ink)");
    var customStyle=document.getElementById("libraryshare-custom-css");
    if(!customStyle){customStyle=document.createElement("style");customStyle.id="libraryshare-custom-css";document.head.appendChild(customStyle);}
    customStyle.textContent=branding.custom_css || "";
    if (X.config && !preview) X.config.branding = Object.assign({},branding);
    var hero=document.querySelector(".welcome h1"), lead=document.querySelector(".welcome .lead"), footer=document.querySelector(".footer"), mark=document.querySelector(".brand-mark");
    if (!brandingDefaults) brandingDefaults={hero:hero.innerHTML,lead:lead.textContent,footer:footer.lastElementChild.textContent};
    var name=branding.name || branding.site_name || "LibraryShare";
    document.querySelector(".brand strong").textContent=name;
    document.title=branding.site_name || name;
    document.querySelector(".brand small").textContent=branding.tagline || "Share useful things nearby";
    footer.firstElementChild.textContent=name;
    footer.lastElementChild.textContent=branding.footer_text || brandingDefaults.footer;
    if (branding.homepage_hero_title) hero.textContent=branding.homepage_hero_title;
    else hero.innerHTML=brandingDefaults.hero;
    lead.textContent=branding.homepage_hero_body || brandingDefaults.lead;
    [["primary_color","--green"],["accent_color","--amber"],["background_color","--page-background"],["foreground_color","--ink"]].forEach(function(pair){
      style.setProperty(pair[1],/^#[a-f0-9]{6}$/i.test(branding[pair[0]] || "") ? branding[pair[0]] : preset[pair[0]]);
    });
    var logo=X.safeBrandUrl(branding.logo_url);
    mark.textContent="LS";
    if(logo){var img=document.createElement("img");img.src=logo;img.alt="";img.referrerPolicy="no-referrer";img.addEventListener("error",function(){mark.textContent="LS";});mark.textContent="";mark.appendChild(img);}
    var icon=document.getElementById("libraryshare-favicon"), iconUrl=X.safeBrandUrl(branding.favicon_url);
    if(iconUrl){if(!icon){icon=document.createElement("link");icon.id="libraryshare-favicon";icon.rel="icon";document.head.appendChild(icon);}icon.href=iconUrl;}
    else if(icon)icon.remove();
    var account=X.safeBrandUrl(branding.koha_public_url) || "/cgi-bin/koha/opac-user.pl";
    document.querySelectorAll('a[data-koha-link],a[href="/cgi-bin/koha/opac-user.pl"]').forEach(function(link){link.dataset.kohaLink="1";link.href=account;});
    var website=document.getElementById("libraryshare-website"), websiteUrl=X.safeBrandUrl(branding.library_website_url);
    if(websiteUrl){if(!website){website=document.createElement("a");website.id="libraryshare-website";website.className="text-link";website.textContent="Library website";website.target="_blank";website.rel="noopener noreferrer";document.querySelector(".top-actions").appendChild(website);}website.href=websiteUrl;}
    else if(website)website.remove();
  };
  X.table = function (title, rows, columns) {
    if (!rows || !rows.length) return empty("No " + title.toLowerCase() + " yet.");
    return '<div class="table-wrap"><table><caption>' + e(title) + '</caption><thead><tr>' + columns.map(function(c){return '<th scope="col">' + e(c[0]) + '</th>';}).join("") + '</tr></thead><tbody>' + rows.map(function(row){
      return '<tr>' + columns.map(function(c){return '<td>' + (typeof c[1] === "function" ? c[1](row) : e(row[c[1]])) + '</td>';}).join("") + '</tr>';
    }).join("") + '</tbody></table></div>';
  };
  X.field = function (label, name, value, type, options) {
    options = options || {};
    var attributes = ' name="' + e(name) + '" ' + (options.required ? 'required ' : '') + (options.min != null ? 'min="' + e(options.min) + '" ' : '') + (options.max != null ? 'max="' + e(options.max) + '" ' : '') + (options.step ? 'step="' + e(options.step) + '" ' : '') + (options.maxlength ? 'maxlength="' + num(options.maxlength) + '" ' : '');
    var control;
    if (type === "textarea") control = '<textarea rows="5"' + attributes + '>' + e(value) + '</textarea>';
    else if (type === "select") control = '<select' + attributes + '>' + (options.choices || []).map(function (choice) { var v = Array.isArray(choice) ? choice[0] : choice, text = Array.isArray(choice) ? choice[1] : choice; return '<option value="' + e(v) + '"' + (String(v) === String(value) ? ' selected' : '') + '>' + e(text) + '</option>'; }).join("") + '</select>';
    else if (type === "checkbox") control = '<input type="checkbox"' + attributes + (value === true || value === 1 || value === "1" ? ' checked' : '') + '>';
    else control = '<input type="' + e(type || "text") + '"' + attributes + ' value="' + e(value == null ? "" : value) + '">';
    return '<label class="' + (options.wide ? 'wide ' : '') + (type === "checkbox" ? 'check-label' : '') + '">' + e(label) + control + '</label>';
  };
  function submit(label) { return '<button class="button button-dark" type="submit">' + e(label || "Save changes") + '</button>'; }
  X.saveButton = submit;
  X.modal = function (title, html) {
    if (!dialog) {
      dialog = document.createElement("dialog"); dialog.className = "dialog";
      document.getElementById("libraryshare-app").appendChild(dialog);
      dialog.addEventListener("close", function () { document.body.classList.remove("print-certificate"); if (lastFocus && lastFocus.isConnected) lastFocus.focus(); });
      dialog.addEventListener("click",function(event){ if (event.target === dialog) dialog.close(); });
    }
    if (!dialog.open) lastFocus = document.activeElement;
    dialog.innerHTML = '<div class="dialog-header"><h2 id="ls-dialog-title">' + e(title) + '</h2><button type="button" class="close-button" data-action="close-dialog" aria-label="Close dialog">&times;</button></div><div class="dialog-body"><div id="dialog-error" class="dialog-error" role="alert" hidden></div>' + html + '</div>';
    dialog.querySelectorAll('a[href="/cgi-bin/koha/opac-user.pl"]').forEach(function(link){link.dataset.kohaLink="1";link.href=X.kohaUrl();});
    dialog.setAttribute("aria-labelledby","ls-dialog-title");
    if (!dialog.open) dialog.showModal();
  };
  X.close = function () { if(dialog && dialog.open) dialog.close(); };
  X.resetProfile = function () { profileId = null; };
  function dialogError(error) {
    var node = document.getElementById("dialog-error");
    if (dialog && dialog.open && node) { node.hidden = false; node.textContent = error.message; node.scrollIntoView({block:"nearest"}); }
    B.notice(error.message,true);
  }
  X.dialogError = dialogError;
  X.ensureAgreements = async function () {
    var data = await ext("agreements");
    if ((data.pending || []).length) {
      if (dialog && dialog.open && !dialog.querySelector('[data-ext="agreements"]')) {
        suspendedDialog=document.createDocumentFragment();
        while(dialog.firstChild)suspendedDialog.appendChild(dialog.firstChild);
      }
      X.modal("Before you lend or borrow", '<p class="form-hint">Please read and accept the current lending documents. Your form will remain available after acceptance.</p>' + documentsHtml(data.documents || [], data));
      throw new Error("Please accept the current lending terms and waiver, then submit again.");
    }
  };
  function documentsHtml(documents, agreements) {
    var pending = agreements && agreements.pending || [], accepted = agreements && agreements.acceptances || [];
    return documents.map(function (doc) {
      var needs = pending.some(function(row){return (typeof row === "string" ? row : row.document_key) === doc.document_key;});
      var previous = accepted.filter(function(row){return row.document_key === doc.document_key;});
      return '<article class="document"><p class="eyebrow">' + e(doc.document_key) + ' · version ' + e(doc.version) + (num(doc.required) ? ' · required' : '') + '</p><h3>' + e(doc.title) + '</h3><div class="document-body">' + e(doc.body) + '</div>' + (previous.length ? '<p class="form-hint">Acceptance recorded: ' + previous.map(function(a){return e(a.version || a.document_version) + (a.accepted_at ? ' · ' + e(a.accepted_at) : '');}).join(", ") + '</p>' : '') + (needs ? '<p class="status-pill">Your acceptance is needed</p>' : '') + '</article>';
    }).join("") + (B.state.bootstrap.signed_in && pending.length ? '<form data-ext="agreements" class="form-grid"><label class="check-label wide"><input name="agree" type="checkbox" required>I have read and accept the current required documents above.</label><input type="hidden" name="versions" value="' + e(JSON.stringify(Object.fromEntries(documents.filter(function(d){return num(d.required);}).map(function(d){return [d.document_key,d.version];})))) + '">' + submit("Accept current versions") + '</form>' : !B.state.bootstrap.signed_in ? '<p class="form-hint">Sign in through Koha to record acceptance.</p>' : '<p class="form-hint">Your required document acceptances are up to date.</p>');
  }
  async function documentsView() {
    var node = document.getElementById("view-documents");
    node.innerHTML = '<div class="loading">Loading library documents…</div>';
    try {
      var data = B.state.bootstrap.signed_in ? await ext("agreements") : await ext("config");
      node.innerHTML = '<div class="section-head"><div><p class="eyebrow">Safe sharing, clear expectations</p><h2>Help &amp; lending agreements</h2></div></div>' + documentsHtml(data.documents || [],data);
    } catch(error) { node.innerHTML = X.error(error,"retry-documents"); }
  }
  X.init = async function () {
    try {
      X.config = await ext("config");
      X.applyBranding(X.config.branding);
      document.getElementById("staff-tab").hidden = !X.config.is_admin;
    } catch(error) {
      X.applyBranding({});
      var warning=document.createElement("div");warning.className="audit-note";warning.id="configuration-error";warning.setAttribute("role","alert");
      warning.innerHTML='Community appearance could not be loaded. Browse or list items while your administrator checks the configuration endpoint. ' + e(error.message) + ' ' + button("Retry configuration","retry-configuration");
      document.querySelector(".tabs").insertAdjacentElement("afterend",warning);
    }
    try {
      var data = await ext("facets"), form = document.getElementById("facet-form");
      form.elements.category.innerHTML += (data.categories || []).map(function(c){return '<option value="' + e(c.category) + '">' + e(c.category) + ' (' + num(c.count) + ')</option>';}).join("");
      form.elements.branch.innerHTML += (data.branches || []).map(function(b){return '<option value="' + e(b.branchcode) + '">' + e(b.branchname) + '</option>';}).join("");
    } catch(error) { B.notice("Filters unavailable: " + error.message,true); }
    var wanted = document.getElementById("wanted-form");
    wanted.insertAdjacentHTML("beforebegin",'<form id="wanted-filter" class="filters"><label>Show wanted posts<select name="status"><option value="open">Open</option><option value="fulfilled">Fulfilled</option><option value="closed">Closed</option></select></label>' + submit("Show posts") + '</form>');
    if (!B.state.bootstrap.signed_in) {
      wanted.innerHTML = '<p class="muted">Sign in to Koha to post a wanted item.</p><a class="button button-dark" data-koha-link="1" href="' + e(X.kohaUrl()) + '">Sign in</a>';
    }
    var listing = document.getElementById("listing-form");
    listing.querySelector('[name="photos"]').addEventListener("change",function(){ previewFiles(this,listing); });
  };
  function previewFiles(input, form) {
    var old = form.querySelector(".file-preview"); if(old) old.remove();
    var previews = document.createElement("div"); previews.className = "file-preview wide photos"; form.appendChild(previews);
    Array.from(input.files).forEach(function(file){
      if (file.size > 5 * 1024 * 1024 || !/^image\/(jpeg|png|webp)$/.test(file.type)) { B.notice("Use JPEG, PNG or WebP files up to 5 MB each.",true); return; }
      var img = document.createElement("img"); img.className = "photo-preview"; img.alt = file.name;
      var url = URL.createObjectURL(file); img.onload = function(){URL.revokeObjectURL(url);}; img.src = url; previews.appendChild(img);
    });
  }
  async function uploadFiles(files, target, caption) {
    for (var file of Array.from(files || [])) {
      if (file.size > 5 * 1024 * 1024 || !/^image\/(jpeg|png|webp)$/.test(file.type)) throw new Error("Photos must be JPEG, PNG or WebP and no larger than 5 MB.");
      var data = await new Promise(function(resolve,reject){var reader=new FileReader();reader.onload=function(){resolve(reader.result);};reader.onerror=function(){reject(new Error("Could not read photo."));};reader.readAsDataURL(file);});
      await ext("photos",Object.assign({},target,{data:data,caption:caption || file.name}));
    }
  }
  X.afterListingCreated = async function (result, form) {
    var id = result.id || result.listing_id;
    var files = form.elements.photos.files;
    if (files.length && !id) { B.notice("Listing created, but the server did not return its ID. Add photos from the listing detail.",true); return; }
    if (files.length) {
      try { await uploadFiles(files,{listing_id:num(id)}); }
      catch(error) { X.modal("Listing saved; photos need attention",'<p>' + e(error.message) + '</p><p>Your listing was created. Do not submit it again. Add photos from its detail page.</p>' + button("Open listing","detail",id)); }
    }
    var wantedId = form.dataset.wanted;
    if (wantedId && id) {
      delete form.dataset.wanted;
      try { await ext("fulfil",{wanted_id:num(wantedId),listing_id:num(id)}); }
      catch(error) { X.modal("Listing saved; wish not connected",'<p>' + e(error.message) + '</p><p>The item was created successfully. Return to the wanted post and offer this existing listing; do not create it again.</p>' + button("Open listing","detail",id)); }
    }
    var preview = form.querySelector(".file-preview"); if(preview)preview.remove();
  };
  function photoHtml(photos, owner) {
    return '<div class="photos">' + (photos || []).map(function(p) {
      var url = X.image(p.url); if (!url) return "";
      return '<figure class="photo-tile"><a href="' + e(url) + '" target="_blank" rel="noopener"><img loading="lazy" src="' + e(url) + '" alt="' + e(p.caption || "Shared item photo") + '"></a><figcaption>' + e(p.caption || "") + '</figcaption>' + (owner ? button("Remove photo","remove-photo",p.id,' data-listing="' + num(p.listing_id) + '" data-review="' + num(p.review_id) + '"') : '') + '</figure>';
    }).join("") + '</div>';
  }
  function photosForm(target) {
    return '<form data-ext="photos" data-listing="' + num(target.listing_id) + '" data-review="' + num(target.review_id) + '" class="form-grid">' + X.field("Caption","caption","","text",{maxlength:200}) + '<label>Photos<input type="file" name="files" accept="image/jpeg,image/png,image/webp" multiple required><span class="form-hint">Maximum 5 MB per image.</span></label>' + submit("Upload photos") + '</form>';
  }
  X.detail = async function (id) {
    X.modal("Item details",'<div class="loading">Loading item and availability…</div>');
    try {
      var results = await Promise.all([B.api("/listings/" + num(id)),ext("photos?listing_id=" + num(id)),ext("availability?listing_id=" + num(id))]);
      var l = results[0].listing || {}, owner = num(l.owner_borrowernumber) === B.patronId(), a = results[2];
      X.modal(l.title || "Item details",'<div class="detail-layout"><div>' + photoHtml(results[1].photos,owner) + '<p class="eyebrow">' + e(l.category) + '</p><p class="body-copy">' + e(l.description || "No description provided.") + '</p>' + (l.author ? '<p>Maker / author: ' + e(l.author) + '</p>' : '') + '</div><div><dl class="detail-meta"><div><dt>Condition</dt><dd>' + e(l.item_condition) + '</dd></div><div><dt>Loan length</dt><dd>' + num(l.default_loan_days) + ' days</dd></div><div><dt>Pickup branch</dt><dd>' + e(l.pickup_branch) + '</dd></div><div><dt>Meeting place</dt><dd>' + e(l.pickup_location || "Arrange a public meeting") + '</dd></div><div><dt>Status</dt><dd>' + e(l.status) + '</dd></div></dl><p>Shared by ' + button([l.firstname,l.surname].filter(Boolean).join(" ") || "Library member","profile",l.owner_borrowernumber) + '</p><div class="toolbar">' + (owner ? button("Edit listing","edit-listing",l.id) + button("Add pickup availability","add-slot",l.id) : B.state.bootstrap.signed_in ? button("Request item","request",l.id) + button("Report a concern","report",l.id) : '<a class="button button-dark" href="/cgi-bin/koha/opac-user.pl">Sign in to request</a>') + '</div></div></div><h3 class="subhead">Pickup availability</h3><p class="form-hint">An open meeting slot does not guarantee the item is available for the whole loan period. Confirm your dates with the lender.</p>' + X.table("Open pickup slots",a.slots || [],[["Starts","starts_at"],["Ends","ends_at"],["Location","location"],["Status",function(row){return e(row.status || "open");}]]) + X.table("Reserved loan periods",a.loans || [],[["From","starts_at"],["Until","ends_at"],["Status","status"]]) + (owner ? '<h3 class="subhead">Add item photos</h3>' + photosForm({listing_id:l.id}) : ''));
      dialog.querySelector(".detail-meta").insertAdjacentHTML("afterbegin",'<div><dt>Estimated item value (not a fee)</dt><dd>' + X.itemValue(l.estimated_value) + '</dd></div>');
    } catch(error) { X.modal("Item details",X.error(error) + button("Retry item","detail",id)); }
  };
  async function editListing(id) {
    X.modal("Edit your listing",'<div class="loading">Loading listing…</div>');
    try {
      var l = (await B.api("/listings/" + num(id))).listing;
      var choices = (B.state.bootstrap.branches || []).map(function(b){return [b.branchcode,b.branchname];});
      X.modal("Edit your listing",'<form data-ext="edit-listing" data-id="' + num(id) + '" class="form-grid">' +
        X.field("Item name","title",l.title,"text",{required:true,maxlength:200}) + X.field("Maker or author","author",l.author,"text",{maxlength:200}) +
        X.field("Category","category",l.category,"text",{required:true,maxlength:80}) + X.field("Condition","item_condition",l.item_condition,"select",{choices:["excellent","good","fair"]}) +
        X.field("Pickup branch","pickup_branch",l.pickup_branch,"select",{choices:choices}) + X.field("Public meeting place","pickup_location",l.pickup_location,"text",{maxlength:200}) +
        X.field("Loan length (days)","default_loan_days",l.default_loan_days,"number",{min:1,max:90,required:true}) +
        X.field("Estimated item value ($)","estimated_value",l.estimated_value,"number",{min:0,max:99999999.99,step:"0.01",required:l.estimated_value!=null}) +
        '<p class="wide form-hint">Not a fee. Each completed loan saves an estimated 50% of this value. Changing it recalculates past savings. Older listings may stay unset until valued.</p>' +
        X.field("Description","description",l.description,"textarea",{wide:true,maxlength:4000}) + '<p class="wide form-hint">Existing Koha checkouts keep their original due dates.</p>' + submit("Save listing") + '</form>');
    } catch(error) { dialogError(error); }
  }
  X.wantedControls = function (item) {
    return (item.status !== "fulfilled" ? button("Mark fulfilled","wanted-status",item.id,' data-status="fulfilled"') : '') + button(item.status === "open" || !item.status ? "Close post" : "Reopen post","wanted-status",item.id,' data-status="' + (item.status === "open" || !item.status ? "closed" : "open") + '"');
  };
  X.loadMatches = async function () {
    var node = document.getElementById("wanted-matches"); if(!node)return;
    if (!B.state.bootstrap.signed_in) { node.innerHTML = empty("Sign in to see matches for your wishlist."); return; }
    node.innerHTML = '<div class="loading">Finding matches…</div>';
    try { var data = await ext("matches"); node.innerHTML = (data.matches || []).map(function(m){return '<article class="wanted-row"><div><h3>' + e(m.title) + '</h3><p>Matches “' + e(m.wanted_title) + '” · ' + e(m.category) + '</p></div>' + button("View item","detail",m.listing_id) + '</article>';}).join("") || empty("No matching items yet. Check back as your neighbors add listings."); }
    catch(error) { node.innerHTML = X.error(error,"retry-matches"); }
  };
  async function offerWanted(id) {
    var wanted = B.state.wanted.find(function(w){return num(w.id) === num(id);});
    if(!wanted)return;
    X.modal("Lend something for this wish",'<div class="loading">Loading your items…</div>');
    try {
      var mine = (await B.api("/dashboard")).listings || [];
      X.modal("Help with “" + wanted.title + "”",'<p class="form-hint">Connect an existing item, or create a listing with the wish already filled in. The requester will be notified.</p>' + (mine.filter(function(l){return l.status === "active";}).length ? '<form data-ext="fulfil" class="form-grid" data-id="' + num(id) + '">' + X.field("Your item","listing_id","","select",{required:true,choices:mine.filter(function(l){return l.status === "active";}).map(function(l){return [l.id,l.title];})}) + submit("Offer this item") + '</form>' : empty("You have no active listings to offer yet.")) + button("Create a listing for this wish","prefill-wanted",id));
    } catch(error) { dialogError(error); }
  }
  X.requestControls = function (r, owner) {
    return button("History","history",r.id) + (r.status === "accepted" && owner ? button("Use an available pickup slot","schedule-existing",r.id) : '') + (r.status === "approved" && owner ? button("Reschedule pickup","reschedule",r.id) : '') + (["pending","accepted","approved"].indexOf(r.status) >= 0 ? button("Cancel request","cancel-request",r.id) : '');
  };
  function requestById(id) { return (B.state.dashboard && B.state.dashboard.requests || []).find(function(r){return num(r.id) === num(id);}); }
  async function history(id) {
    X.modal("Circulation & handoff history",'<div class="loading">Loading history…</div>');
    try { var data=await ext("history?request_id=" + num(id)); X.modal("Circulation & handoff history",'<ol class="timeline">' + (data.events || []).map(function(ev){return '<li><strong>' + e(ev.event_kind || ev.action || "Updated") + '</strong><p>' + e(ev.created_at || "") + '</p><p>' + e(ev.to_location || "") + ' ' + e(ev.to_starts_at || "") + '</p>' + (ev.to_due_date ? '<p>Koha due date: ' + e(ev.to_due_date) + '</p>' : '') + '<p>' + e(ev.note || ev.notes || "") + '</p></li>';}).join("") + '</ol>' + (!(data.events || []).length ? empty("No handoff changes have been recorded for this request.") : '')); }
    catch(error){X.modal("Request history",X.error(error) + button("Try again","history",id));}
  }
  async function reschedule(id) {
    var r=requestById(id); if(!r)return;
    X.modal("Reschedule pickup",'<div class="loading">Loading open meeting times…</div>');
    try {
      var slots=(await B.api("/slots?listing_id=" + num(r.listing_id))).slots || [];
      X.modal("Reschedule pickup",'<p class="audit-note">Only the pickup meeting changes. The current Koha due date stays ' + e(r.due_date || "unchanged") + '. Use Koha circulation for any permitted renewal.</p>' + (slots.length ? '<form data-ext="reschedule" data-id="' + num(id) + '" class="form-grid">' + X.field("New meeting","slot_id","","select",{required:true,choices:slots.map(function(s){return [s.id,s.starts_at + " · " + s.location];})}) + X.field("Note to borrower","notes","","textarea",{maxlength:1000,wide:true}) + submit("Move pickup meeting") + '</form>' : empty("No open pickup times. Add a new slot, then return here.")) + button("Add pickup slot","add-slot",r.listing_id));
    } catch(error){dialogError(error);}
  }
  async function scheduleExisting(id) {
    var r=requestById(id);if(!r)return;
    X.modal("Schedule pickup & checkout",'<div class="loading">Loading open pickup times…</div>');
    try {
      var slots=(await B.api("/slots?listing_id=" + num(r.listing_id))).slots || [];
      X.modal("Schedule pickup & checkout",'<p class="audit-note">Confirm the handoff with the borrower first. Booking creates a real Koha checkout, subject to Koha circulation rules.</p>' + (slots.length ? '<form data-ext="schedule-existing" data-id="' + num(id) + '" class="form-grid">' + X.field("Available pickup time","slot_id","","select",{required:true,choices:slots.map(function(s){return [s.id,s.starts_at + " · " + s.location];})}) + X.field("Loan days","loan_days",r.listing_default_loan_days || B.state.bootstrap.default_loan_days,"number",{required:true,min:1,max:90}) + X.field("Handoff note","notes","","textarea",{wide:true,maxlength:1000}) + submit("Book pickup & create checkout") + '</form>' : empty("There are no open pickup slots yet.")) + button("Add an available pickup time","add-slot",r.listing_id));
    } catch(error){dialogError(error);}
  }
  function addSlot(id) {
    X.modal("Offer pickup availability",'<p class="form-hint">Choose an inclusive date range (up to 93 days). We create one-hour blocks within the pickup branch’s opening hours, excluding Koha calendar closures, past times and existing slots. All times are library-local. Optional daily limits narrow your availability. This does not create a checkout.</p><form data-ext="slot" data-id="' + num(id) + '" class="form-grid">' +
      X.field("First date","date_from","","date",{required:true}) + X.field("Last date","date_to","","date",{required:true}) +
      X.field("Not before (optional)","daily_start","","time",{}) + X.field("Not after (optional)","daily_end","","time",{}) +
      X.field("Meeting place at pickup branch","location","","text",{required:true,maxlength:200,wide:true}) + submit("Generate one-hour pickup slots") + '</form>');
  }
  function reviewForm(id) {
    X.modal("How did the loan go?",'<form data-ext="review" data-id="' + num(id) + '" class="form-grid">' + X.field("Rating","rating",5,"select",{choices:[[5,"5 — Excellent"],[4,"4 — Good"],[3,"3 — Okay"],[2,"2 — Disappointing"],[1,"1 — Poor"]],required:true}) + X.field("Your review","body","","textarea",{wide:true,maxlength:1000}) + '<label class="wide">Optional review photos<input type="file" name="photos" accept="image/jpeg,image/png,image/webp" multiple><span class="form-hint">JPEG, PNG or WebP. Maximum 5 MB each.</span></label>' + submit("Publish review") + '</form>');
  }
  async function reviewPhotos(id, own) {
    X.modal("Review photos",'<div class="loading">Loading photos…</div>');
    try {var data=await ext("photos?review_id=" + num(id));X.modal("Review photos",photoHtml(data.photos,own) + (!(data.photos || []).length ? empty("No photos attached to this review.") : '') + (own ? photosForm({review_id:id}) : ''));}
    catch(error){dialogError(error);}
  }
  function labelLevel(level) { return typeof level === "object" && level !== null ? level.label || level.level || "New member" : level || "New member"; }
  function readable(key) { return String(key || "").replace(/_/g," ").replace(/\b\w/g,function(c){return c.toUpperCase();}); }
  async function profileView(id) {
    profileId = id || null;
    var node=document.getElementById("view-profile"); node.innerHTML='<div class="loading">Loading member profile…</div>';
    try {
      var data=await ext("profile" + (profileId ? "?patron_id=" + num(profileId) : "")), catalog=await ext("badges");
      profileData=data;
      var p=data.patron || {}, s=data.stats || {}, full=[p.firstname,p.surname].filter(Boolean).join(" ") || "Library member", levels=data.levels || {}, badges=catalog.badges || [];
      data.listings=(data.listings || []).map(function(row){return Object.assign({},row,{is_mine:data.is_self ? 1 : 0,owner_borrowernumber:p.borrowernumber,firstname:p.firstname,surname:p.surname});});
      var initials = [p.firstname,p.surname].filter(Boolean).map(function(v){return v.charAt(0);}).join("");
      node.innerHTML='<div class="section-head"><div class="profile-heading"><span class="avatar-initials" aria-hidden="true">' + e(initials || "LS") + '</span><div><p class="eyebrow">Your neighborhood, your contribution</p><h2>' + e(full) + '</h2><p class="muted">Lender: ' + e(labelLevel(levels.lender)) + ' · Borrower: ' + e(labelLevel(levels.borrower)) + '</p></div></div>' + button("Print / download certificate","certificate") + '</div><div class="stats-row">' +
        [["Lending loans",s.loans_as_lender],["Borrowing loans",s.loans_as_borrower],["Estimated value saved","$"+num(s.est_value_saved).toFixed(2)]].map(function(pair){return '<div class="stat"><strong class="number">' + e(pair[1] == null ? 0 : pair[1]) + '</strong><span>' + e(pair[0]) + '</span></div>';}).join("") +
        '</div><h3 class="subhead">Badge shelf</h3><div class="badge-shelf">' + (data.badges || []).map(function(b){var meta=badges.find(function(c){return c.slug === b.badge_key;}) || {};return '<div class="badge-medal" title="' + e(meta.description || readable(b.badge_key)) + '"><b>' + e(meta.label || readable(b.badge_key)) + '</b><small>' + e(meta.description || "Recognition for community sharing") + '</small><small>' + e(b.earned_at || "") + '</small></div>';}).join("") + '</div>' + (!(data.badges || []).length ? empty("Your first completed loan starts your badge collection.") : '') +
        '<h3 class="subhead">The next chapter</h3><div class="stack">' + (data.goals || []).map(function(g){var progress=num(g.progress), threshold=Math.max(1,num(g.threshold));return '<article class="panel"><h3>' + e(g.label) + '</h3><p class="form-hint">' + progress + ' / ' + threshold + ' · ' + e(readable(g.metric)) + '</p><progress class="progress-track" value="' + Math.min(progress,threshold) + '" max="' + threshold + '" aria-label="' + e(g.label) + '"></progress></article>';}).join("") + '</div>' +
        '<h3 class="subhead">Badge journey</h3>' + X.table("Recognition paths",badges.filter(function(b){return num(b.active);}),[["Badge","label"],["How to earn","description"],["Metric","metric"],["Target","threshold"]]) +
        '<div class="profile-columns"><section><h3 class="subhead">Reviews</h3>' + ((data.reviews || []).map(function(r){return '<article class="panel"><span class="status-pill">' + num(r.rating) + ' / 5 rating</span><p class="body-copy">' + e(r.body || "") + '</p><p class="form-hint">' + e([r.firstname,r.surname].filter(Boolean).join(" ")) + ' · ' + e(r.created_at) + '</p>' + button("Review photos","review-photos",r.id,' data-own="' + (num(r.reviewer_borrowernumber) === B.patronId() ? '1' : '0') + '"') + '</article>';}).join("") || empty("Reviews appear after completed loans.")) + '</section><section><h3 class="subhead">Notes of thanks</h3>' + ((data.kudos || []).map(function(k){return '<article class="panel"><p class="body-copy">' + e(k.message) + '</p><p class="form-hint">' + e(k.created_at) + '</p></article>';}).join("") || empty("Thank-you notes will appear here.")) + '</section></div><h3 class="subhead">Items shared</h3><div class="listing-grid">' + ((data.listings || []).map(B.card).join("") || empty("No active items to show.")) + '</div>' +
        (data.is_self ? '<h3 class="subhead">Your preferences</h3><form data-ext="preferences" class="form-grid">' + X.field("Include me in the public lender leaderboard","show_in_leaderboard",data.preferences && data.preferences.show_in_leaderboard,"checkbox",{wide:true}) + submit("Save preference") + '</form><section id="profile-credits"><div class="loading">Loading credit account…</div></section>' : '');
      if (data.is_self) loadCredits();
    } catch(error){node.innerHTML=X.error(error,"retry-profile");}
  }
  async function loadCredits() {
    var node=document.getElementById("profile-credits"); if(!node)return;
    try {
      var c=await ext("credits"), s=c.settings || {}, stats=profileData && profileData.stats || {}, balance=num(c.balance);
      var perks=[
        {label:"Queue priority",threshold:s.priority_threshold,eligible:balance>=num(s.priority_threshold),details:"Recognizes your contributions in the lending queue."},
        {label:"Longer loans",threshold:s.longer_loan_threshold,eligible:balance>=num(s.longer_loan_threshold),details:num(s.longer_loan_bonus_days) + " bonus days where permitted by the lender and Koha."},
        {label:"Fast-track borrower",threshold:s.fast_track_min_on_time,eligible:num(stats.on_time_returns)>=num(s.fast_track_min_on_time),details:"Based on completed on-time returns, not credit balance.",unit:"on-time returns"}
      ].filter(function(p){return p.threshold != null;});
      node.innerHTML='<div class="panel"><p class="eyebrow">Share credit account</p><h3>' + e(c.balance) + ' credits</h3><p class="form-hint">Borrowing cost: ' + e(s.borrow_credit_cost) + ' · Starting allocation: ' + e(s.starting_credits) + ' · Active request limit: ' + e(s.max_active_requests) + '</p><p class="form-hint">Recognition only: credits cannot be bought, transferred or redeemed for money. Eligibility does not override library circulation rules or extend an existing due date.</p></div>' +
        (num(s.gamification_enabled) === 0 ? '<p class="audit-note">Recognition and perks are currently disabled by your library.</p>' : X.table("Your recognition perks",perks,[["Perk","label"],["Eligibility",function(p){return '<span class="status-pill">' + (p.eligible ? "Threshold reached" : "In progress") + '</span><br>' + e(p.threshold) + ' ' + e(p.unit || "credits");}],["How it works","details"]])) +
        X.table("Ways to earn credits",[
          {label:"Completed lending loan",amount:s.credits_per_completed_loan},{label:"On-time borrowing return",amount:s.credits_per_on_time_return},{label:"First listing",amount:s.credits_first_listing},{label:"Wish fulfilled",amount:s.credits_wanted_fulfilled},{label:"Thank-you note received",amount:s.credits_per_kudos}
        ].filter(function(row){return row.amount != null;}),[["Contribution","label"],["Credits","amount"]]) + ledger(c.ledger || []);
    }
    catch(error){node.innerHTML=X.error(error,"retry-credits");}
  }
  function ledger(rows) { return X.table("Credit ledger",rows,[["When","created_at"],["Change",function(r){return '<span class="number">' + e(r.delta == null ? r.amount : r.delta) + '</span>';}],["Reason",function(r){return e(r.note || r.reason || r.event_kind || "");}],["Balance","balance"]]); }
  function certificate() {
    if(!profileData)return;
    var p=profileData.patron || {}, s=profileData.stats || {};
    X.modal("Community sharing certificate",'<div class="certificate"><p class="eyebrow">' + e(X.config && X.config.branding && X.config.branding.name || "LibraryShare") + '</p><h2>A little sharing.<br>A lasting difference.</h2><p>Recognizing the contribution of</p><p class="recipient">' + e([p.firstname,p.surname].filter(Boolean).join(" ")) + '</p><p><strong>' + num(s.loans_as_lender) + '</strong> completed lending loans<br><strong>' + num(s.distinct_items_lent) + '</strong> different items shared<br><strong>$' + num(s.est_value_saved).toFixed(2) + '</strong> estimated value saved</p><p>50% of each item’s current value per completed loan; unvalued items excluded.</p><p>Recorded through Koha community circulation<br>' + e(new Date().toLocaleDateString()) + '</p></div><div class="toolbar no-print">' + button("Print or save as PDF","print-certificate") + button("Download certificate (HTML)","download-certificate") + '</div><p class="form-hint no-print">Choose “Save as PDF” in your browser’s print dialog for a PDF copy. Savings are estimates, not audited measurements.</p>');
  }
  X.loadImpact = async function () {
    var node=document.getElementById("extended-impact");
    if(!node){node=document.createElement("div");node.id="extended-impact";document.getElementById("view-community").appendChild(node);}
    node.innerHTML='<div class="loading">Loading community analytics…</div>';
    try {
      var d=await ext("impact"), t=d.totals || {};
      node.innerHTML='<h3 class="subhead">The community ledger</h3><div class="panel"><p class="impact-copy">' + num(t.loans) + ' completed loans · $' + num(t.value_saved).toFixed(2) + ' estimated value saved</p><p class="form-hint">50% of each item’s current value per completed loan. ' + num(t.unvalued_loans) + ' completed loans have no item value and are excluded from savings. Value edits recalculate past savings.</p><p class="form-hint">Community goal: ' + e(typeof d.community_goal === "object" ? JSON.stringify(d.community_goal) : d.community_goal || "Not set") + ' · Loan milestone: ' + e(d.milestone_loans || "Not set") + '.</p></div>' +
        (d.featured ? '<div class="panel"><p class="eyebrow">Featured neighbor</p><h3>' + e(d.featured.patron && [d.featured.patron.firstname,d.featured.patron.surname].filter(Boolean).join(" ")) + '</h3>' + button("View lender profile","profile",d.featured.patron && d.featured.patron.borrowernumber) + '</div>' : '') +
        X.table("Loans by month",d.monthly || [],[["Month","month"],["Completed loans","loans"]]) + X.table("Savings by category",d.categories || [],[["Category","category"],["Loans","loans"],["Estimated value saved ($)","value_saved"],["Loans without item value","unvalued_loans"]]) + X.table("Activity by branch",d.branches || [],[["Branch","branchcode"],["Loans","loans"]]);
    } catch(error){node.innerHTML=X.error(error,"retry-impact");}
  };
  X.view = function (name) {
    if(name === "profile") profileView(profileId);
    if(name === "documents") documentsView();
    if(name === "admin") window.LSStaff.view();
  };
  X.action = async function (action, el) {
    if(action==="retry-configuration"){
      try{X.config=await ext("config");X.applyBranding(X.config.branding);document.getElementById("staff-tab").hidden=!X.config.is_admin;var warning=document.getElementById("configuration-error");if(warning)warning.remove();}
      catch(error){B.notice("Configuration still unavailable. Check /extended/config and plugin installation: "+error.message,true);}
      return true;
    }
    var id=el.dataset.id, r;
    try {
      if (action === "close-dialog") X.close();
      else if (action === "request") {
        if(!B.state.bootstrap.signed_in){X.close();B.setView("login");return true;}
        X.modal("Request this item",'<p class="form-hint">Introduce yourself and propose borrowing dates. These dates are a request, not a booking or a Koha due-date extension. The lender confirms pickup and the loan period.</p><form data-ext="request" data-id="' + num(id) + '" class="form-grid">' + X.field("Proposed start (optional)","proposed_start","","date") + X.field("Proposed end (optional)","proposed_end","","date") + X.field("Message to lender (optional)","message","","textarea",{wide:true,maxlength:1000}) + submit("Send borrow request") + '</form>');
      }
      else if (action === "detail") await X.detail(id);
      else if (action === "edit-listing") await editListing(id);
      else if (action === "profile") {X.close();profileId=id || null; B.setView("profile");}
      else if (action === "reset-filters") {document.getElementById("facet-form").reset();document.getElementById("search-query").value="";await B.loadListings();}
      else if (action === "retry-listings") await B.loadListings();
      else if (action === "retry-wanted") await B.loadWanted();
      else if (action === "retry-dashboard") await B.loadDashboard();
      else if (action === "retry-community") await B.loadCommunity();
      else if (action === "retry-documents") await documentsView();
      else if (action === "retry-profile") await profileView(profileId);
      else if (action === "retry-credits") await loadCredits();
      else if (action === "retry-matches") await X.loadMatches();
      else if (action === "retry-impact") await X.loadImpact();
      else if (action === "reload-app") location.reload();
      else if (action === "wanted-status") {await ext("fulfil",{wanted_id:num(id),status:el.dataset.status});B.notice("Wanted post updated.");if(B.state.view === "dashboard")await B.loadDashboard();else await B.loadWanted();}
      else if (action === "offer-wanted") await offerWanted(id);
      else if (action === "prefill-wanted") {
        var w=B.state.wanted.find(function(row){return num(row.id)===num(id);});if(!w)return true;
        X.close();B.setView("add");var form=document.getElementById("listing-form"); form.reset();form.elements.title.value=w.title || "";form.elements.category.value=w.category || "";form.elements.description.value=w.description || "";form.dataset.wanted=id;
        B.notice("Complete your item details. Saving will connect this listing to the wish.");
      }
      else if (action === "history") await history(id);
      else if (action === "reschedule") await reschedule(id);
      else if (action === "schedule-existing" || action === "pickup-form") await scheduleExisting(id);
      else if (action === "add-slot") addSlot(id);
      else if (action === "review") reviewForm(id);
      else if (action === "review-photos") await reviewPhotos(id,el.dataset.own === "1");
      else if (action === "kudos") X.modal("Thank your lender",'<form data-ext="kudos" data-id="' + num(id) + '" class="form-grid">' + X.field("Your thank-you note","message","","textarea",{required:true,maxlength:1000,wide:true}) + submit("Send thanks") + '</form>');
      else if (action === "report") X.modal("Report a concern",'<p class="form-hint">Library staff review these reports. For immediate danger, contact local emergency services.</p><form data-ext="report" data-id="' + num(id) + '" class="form-grid">' + X.field("What should staff know?","reason","","textarea",{required:true,maxlength:2000,wide:true}) + submit("Send report to staff") + '</form>');
      else if (action === "cancel-request") {r=requestById(id);X.modal("Cancel this request?",'<p class="audit-note">' + (r && r.status === "approved" ? 'This is an active Koha checkout. Cancellation must be validated by the server and may be refused. Do not treat a cancellation as a physical return.' : 'The other participant will be able to see this cancellation in the handoff history.') + '</p><form data-ext="cancel" data-id="' + num(id) + '" class="form-grid">' + X.field("Reason / note","notes","","textarea",{required:true,maxlength:1000,wide:true}) + submit("Confirm cancellation") + '</form>');}
      else if (action === "remove-photo") {if(!window.confirm("Permanently remove this photo?"))return true;await ext("photos",{id:num(id),remove:true});B.notice("Photo removed.");if(num(el.dataset.review))await reviewPhotos(el.dataset.review,true);else await X.detail(el.dataset.listing);}
      else if (action === "notifications-bulk" || action === "dismiss-notification") {
        var ids=action === "dismiss-notification" ? [num(id)] : (B.state.notifications || []).map(function(n){return num(n.id);});
        if(!ids.length){B.notice("There are no notifications to update.");return true;}
        await ext("notifications",{ids:ids,action:action === "dismiss-notification" ? "dismiss" : el.dataset.mode});await B.loadNotifications();
      }
      else if (action === "certificate") {certificate();dialog.querySelector(".toolbar").insertAdjacentHTML("beforeend",button("Download PNG","png-certificate"));}
      else if (action === "png-certificate") {
        var canvas=document.createElement("canvas");canvas.width=1600;canvas.height=1000;
        var ctx=canvas.getContext("2d"),p=profileData.patron || {},s=profileData.stats || {};
        ctx.fillStyle="#faf7e9";ctx.fillRect(0,0,1600,1000);ctx.strokeStyle="#1c4d42";ctx.lineWidth=4;ctx.strokeRect(40,40,1520,920);ctx.strokeRect(54,54,1492,892);
        ctx.fillStyle="#1c4d42";ctx.textAlign="center";
        function line(text,y,size){ctx.font=size+"px Georgia";ctx.fillText(String(text),800,y,1380);}
        line(X.config.branding.name || "LibraryShare",150,36);
        line("Community sharing certificate",270,58);
        line("Recognizing the contribution of",360,30);
        line([p.firstname,p.surname].filter(Boolean).join(" "),450,54);
        line(num(s.loans_as_lender)+" completed loans · "+num(s.distinct_items_lent)+" items shared",565,34);
        line("$"+num(s.est_value_saved).toFixed(2)+" estimated value saved",635,32);
        line("Recorded through Koha community circulation",760,27);
        line(new Date().toLocaleDateString(),820,25);
        line("Impact figures are estimates, not audited measurements.",900,22);
        canvas.toBlob(function(blob){if(!blob){B.notice("PNG export failed.",true);return;}var url=URL.createObjectURL(blob),a=document.createElement("a");a.href=url;a.download="libraryshare-certificate.png";a.click();setTimeout(function(){URL.revokeObjectURL(url);},1000);},"image/png");
      }
      else if (action === "print-certificate") {document.body.classList.add("print-certificate");window.print();}
      else if (action === "download-certificate") {
        var content=document.querySelector(".certificate");if(!content)return true;
        var blob=new Blob(['<!doctype html><html lang="en"><meta charset="utf-8"><title>LibraryShare certificate</title><style>body{font:18px/1.7 Georgia,serif;background:#faf7e9;color:#1c4d42;padding:48px;text-align:center}.certificate{padding:36px;border:5px double #92a17e}h2{font-size:36px}.recipient{font-size:28px;font-style:italic}</style>' + content.outerHTML + '</html>'],{type:"text/html"});
        var url=URL.createObjectURL(blob),a=document.createElement("a");a.href=url;a.download="libraryshare-certificate.html";a.click();setTimeout(function(){URL.revokeObjectURL(url);},1000);
      }
      else if (window.LSStaff && await window.LSStaff.action(action,el)) return true;
      else return false;
      return true;
    } catch(error){dialogError(error);return true;}
  };
  X.submit = async function (form) {
    if(form.id === "facet-form"){await B.loadListings();return true;}
    if(form.id === "wanted-filter"){X.wantedStatus=form.elements.status.value;await B.loadWanted();return true;}
    if(window.LSStaff && form.dataset.staff){return window.LSStaff.submit(form);}
    var kind=form.dataset.ext;if(!kind)return false;
    var values=B.form(form),id=num(form.dataset.id),submitter=form.querySelector('[type="submit"]');
    if(submitter)submitter.disabled=true;
    try {
      if(kind === "agreements"){
        await ext("agreements",{versions:JSON.parse(values.versions)});
        if(suspendedDialog && dialog && dialog.open){dialog.innerHTML="";dialog.appendChild(suspendedDialog);suspendedDialog=null;}
        else X.close();
        if(B.state.view === "documents")await documentsView();
        B.notice("Acceptance recorded. You can now submit your lending action.");return true;
      }
      if(kind === "edit-listing"){values.default_loan_days=num(values.default_loan_days);if(values.estimated_value==="")delete values.estimated_value;await B.api("/listings/" + id,{method:"POST",body:values});X.close();B.notice("Listing updated. Savings use the current item value.");if(B.state.view === "dashboard")await B.loadDashboard();else if(B.state.view === "profile")await profileView(profileId);else await B.loadListings();}
      else if(kind === "request"){
        if(values.proposed_start && values.proposed_end && values.proposed_end < values.proposed_start)throw new Error("The proposed end must be on or after the proposed start.");
        var payload={listing_id:id,message:values.message};
        if(values.proposed_start)payload.proposed_start=values.proposed_start;
        if(values.proposed_end)payload.proposed_end=values.proposed_end;
        await B.api("/requests",{method:"POST",body:payload});X.close();B.notice("Your request was sent to the lender.");B.setView("dashboard");
      }
      else if(kind === "photos"){await uploadFiles(form.elements.files.files,num(form.dataset.review) ? {review_id:num(form.dataset.review)} : {listing_id:num(form.dataset.listing)},values.caption);B.notice("Photos uploaded.");if(num(form.dataset.review))await reviewPhotos(form.dataset.review,true);else await X.detail(form.dataset.listing);}
      else if(kind === "fulfil"){await ext("fulfil",{wanted_id:id,listing_id:num(values.listing_id)});X.close();B.notice("Your item was connected to the wish.");await B.loadWanted();}
      else if(kind === "slot"){
        if(values.date_to < values.date_from)throw new Error("The last date must be on or after the first date.");
        var generated=await B.api("/listings/" + id + "/slots",{method:"POST",body:values});
        await X.detail(id);
        var feedback=document.createElement("p");
        feedback.className="audit-note";
        feedback.setAttribute("role","status");
        feedback.textContent=generated.created ? generated.created + " one-hour pickup slots added." : generated.message;
        dialog.querySelector(".dialog-body").prepend(feedback);
        B.notice(feedback.textContent,!generated.created);
      }
      else if(kind === "reschedule" || kind === "cancel"){await B.api("/requests/" + id + "/" + (kind === "cancel" ? "cancel" : "reschedule"),{method:"POST",body:kind === "cancel" ? {notes:values.notes} : {slot_id:num(values.slot_id),notes:values.notes}});X.close();B.notice("Request updated. Original checkout due dates have not been extended.");await B.loadDashboard();}
      else if(kind === "schedule-existing"){await B.api("/requests/" + id + "/schedule",{method:"POST",body:{slot_id:num(values.slot_id),loan_days:num(values.loan_days),notes:values.notes}});X.close();B.notice("Pickup booked and the Koha checkout is active.");await B.loadDashboard();}
      else if(kind === "review"){
        var result=await B.api("/reviews",{method:"POST",body:{request_id:id,rating:num(values.rating),body:values.body}});
        if(form.elements.photos.files.length){
          var reviewId=result.id || result.review_id;
          if(!reviewId){X.modal("Review saved",'<p>The server saved your review without returning its ID. Open the recipient’s profile to add photos to your review. Do not submit this review again.</p>');return true;}
          try{await uploadFiles(form.elements.photos.files,{review_id:num(reviewId)});}catch(error){X.modal("Review saved; photos need attention",'<p>' + e(error.message) + '</p>' + photosForm({review_id:reviewId}));return true;}
        }
        X.close();B.notice("Your review was published.");await B.loadDashboard();
      }
      else if(kind === "kudos"){await B.api("/kudos",{method:"POST",body:{request_id:id,message:values.message}});X.close();B.notice("Your thanks were sent.");}
      else if(kind === "report"){await ext("reports",{listing_id:id,reason:values.reason});X.close();B.notice("Your report was sent to library staff.");}
      else if(kind === "preferences"){await ext("profile",{show_in_leaderboard:form.elements.show_in_leaderboard.checked});B.notice("Your preference was saved.");}
      return true;
    } catch(error){dialogError(error);return true;}
    finally {if(submitter)submitter.disabled=false;}
  };
})();

(function () {
  "use strict";
  var X=window.LSExt, B, current="reports", data={}, config={}, catalogs={}, content, generation=0;
  var S=window.LSStaff={};
  var sections=[["reports","Reports"],["listings","Listings"],["photos","Photos"],["reviews","Reviews"],["kudos","Thank-you notes"],["users","Users & roles"],["branding","Branding"],["legal","Legal & help"],["settings","Circulation & incentives"],["challenges","Challenges"],["badges","Badge catalog"],["impact","Impact & analytics"],["credits","Credits & recompute"],["audit","Moderation audit"],["diagnostics","Koha diagnostics"]];
  function e(value){return B.escape(value);}
  function n(value){return Number(value || 0);}
  function button(label,action,id,attrs){return X.button(label,action,id,attrs);}
  function field(label,name,value,type,opts){return X.field(label,name,value,type,opts);}
  function form(kind,body,id){return '<form data-staff="' + e(kind) + '" data-id="' + e(id == null ? "" : id) + '" class="form-grid">' + body + X.saveButton() + '</form>';}
  function name(row){return [row.firstname,row.surname].filter(Boolean).join(" ") || row.name || "Library member";}
  function mod(entity,id,action,label){return button(label || (action === "restore" ? "Restore" : "Remove"),"staff-moderate",id,' data-entity="' + e(entity) + '" data-operation="' + e(action) + '"');}
  function reloadButton(){return button("Refresh section","staff-section",current);}
  function header(title,description){return '<div class="section-head"><div><p class="eyebrow">LibraryShare staff workbench</p><h2>' + e(title) + '</h2>' + (description ? '<p class="muted">' + e(description) + '</p>' : '') + '</div>' + reloadButton() + '</div>';}
  S.cancelPreview=function(){if(current==="branding")X.applyBranding(config.branding || {},true);};
  function restoreBranding(){
    S.cancelPreview();
    content.innerHTML=render("branding");
  }
  function previewBranding(event){
    var target=event.target, editor=target.closest('[data-staff="branding"]');
    if(!editor)return;
    if(target.name==="theme_preset" && event.type==="change"){
      var preset=X.brandPresets[target.value];
      if(preset)["primary_color","accent_color","background_color","foreground_color"].forEach(function(key){editor.elements[key].value=preset[key];});
    }
    X.applyBranding(B.form(editor),true);
    var status=editor.querySelector("[data-branding-status]");
    if(status)status.textContent="Local preview only — save to apply these changes for all users.";
    var sample=editor.querySelector("[data-branding-title]");
    if(sample)sample.textContent=editor.elements.name.value || "LibraryShare";
  }
  document.addEventListener("input",previewBranding);
  document.addEventListener("change",previewBranding);
  S.view=async function(){
    B=X.context;
    var node=document.getElementById("view-admin");
    if(!X.config || !X.config.is_admin){node.innerHTML=X.empty("LibraryShare administration or Koha plugin-management permission is required.");return;}
    node.innerHTML='<div class="admin-layout"><nav class="admin-nav" aria-label="Staff console">' + sections.map(function(section){return button(section[1],"staff-section",section[0]);}).join("") + '</nav><div id="staff-content" class="admin-content"></div></div>';
    content=document.getElementById("staff-content");
    await load(current);
  };
  async function load(section){
    if(!content || !content.isConnected)return;
    S.cancelPreview();
    current=section;var token=++generation;
    document.querySelectorAll(".admin-nav button").forEach(function(el){el.classList.toggle("active",el.dataset.id===current);el.setAttribute("aria-current",el.dataset.id===current ? "page" : "false");});
    content.innerHTML='<div class="loading">Loading staff records…</div>';
    try {
      var promises=[X.ext("config")];
      if(["reports","listings","photos","reviews","kudos","users","audit","challenges","impact"].indexOf(section)>=0)promises.push(X.ext("admin"));
      else promises.push(Promise.resolve({}));
      if(section==="badges")promises.push(X.ext("badges"));
      if(section==="impact")promises.push(X.ext("impact"));
      if(section==="diagnostics")promises.push(X.ext("diagnostics"));
      if(section==="challenges")promises.push(B.api("/challenges"));
      var result=await Promise.all(promises);
      if(token!==generation)return;
      config=result[0];X.config=config;data=result[1];catalogs=result[2] || {};
      content.innerHTML=render(section);
    }catch(error){if(token===generation)content.innerHTML=X.error(error,"staff-retry");}
  }
  function render(section){
    if(section==="reports")return header("Reports","Read the concern, review the item, then record a resolution.") + X.table("Member reports",data.reports || [],[["ID","id"],["Item",function(r){return button(r.title || r.listing_title || "Listing " + r.listing_id,"detail",r.listing_id);}],["Concern","reason"],["Status","status"],["Submitted","created_at"],["Action",function(r){return r.status === "resolved" || r.status === "dismissed" ? e(r.note || "Reviewed") : button("Resolve","staff-report",r.id,' data-status="resolved"') + button("Dismiss","staff-report",r.id,' data-status="dismissed"');}]]);
    if(section==="listings")return header("Listing moderation","Removal hides the listing; it does not delete its Koha catalog record.") + X.table("All listings",data.listings || [],[["Item",function(r){return e(r.title) + '<br><small>#' + n(r.id) + '</small>';}],["Owner",function(r){return e(r.owner_name || name(r)) + '<br>' + e(r.owner_borrowernumber);}],["Category","category"],["Status","status"],["Action",function(r){return (r.status!=="removed" ? button("Inspect","detail",r.id) : '') + mod("listing",r.id,r.status==="removed" ? "restore" : "remove");}]]);
    if(section==="photos")return header("Photo moderation","Photos are permanently removed. Record a clear reason for the audit trail.") + X.table("Listing and review photos",data.photos || [],[["Photo",function(p){var url=X.image(p.url);return url ? '<a href="' + e(url) + '" target="_blank" rel="noopener"><img class="photo-preview" width="120" src="' + e(url) + '" alt="' + e(p.caption || "Photo for moderation") + '"></a>' : e(p.id);}],["Context",function(p){return (p.listing_id ? button(p.listing_title || "Item " + p.listing_id,"detail",p.listing_id) : 'Review #' + n(p.review_id)) + '<br>' + e(p.caption || "");}],["Uploaded","created_at"],["Action",function(p){return mod("photo",p.id,"remove","Delete photo");}]]);
    if(section==="reviews")return header("Review moderation","Inspect review photos separately. Deletion cannot be undone.") + X.table("Reviews",data.reviews || [],[["ID","id"],["Rating","rating"],["Review","body"],["Author",function(r){return e(r.reviewer_borrowernumber);}],["Date","created_at"],["Action",function(r){return button("Photos","review-photos",r.id) + mod("review",r.id,"remove","Delete review");}]]);
    if(section==="kudos")return header("Thank-you notes","Moderate member kudos with an audit reason.") + X.table("Thank-you notes",data.kudos || [],[["ID","id"],["Message","message"],["From","sender_borrowernumber"],["To","recipient_borrowernumber"],["Date","created_at"],["Action",function(r){return mod("kudos",r.id,"remove","Delete note");}]]);
    if(section==="users")return header("Users & roles","Only staff with Koha plugin-management permission can grant or revoke the LibraryShare admin role.") + '<p class="audit-note">A LibraryShare role never grants Koha circulation or system permissions. Every role change requires a reason and is recorded.</p>' + form("role",field("Koha patron number","patron_id","","number",{required:true,min:1}) + field("Role action","action","grant","select",{choices:[["grant","Grant LibraryShare admin"],["revoke","Revoke LibraryShare admin"]]}) + field("Reason","reason","","textarea",{required:true,wide:true,maxlength:1000})) + X.table("Members",data.users || [],[["Patron","borrowernumber"],["Name",function(r){return button(name(r),"profile",r.borrowernumber);}],["Role",function(r){return e(r.role || "member");}],["Action",function(r){return mod("role",r.borrowernumber,r.role==="admin" ? "revoke" : "grant",r.role==="admin" ? "Revoke admin" : "Grant admin");}]]);
    if(section==="branding"){
      var branding=X.brandValues(config.branding);
      return header("Make this space your own","Preview changes here first. Save changes to apply the design for all users, including on their next visit. Cancel and Reset to saved only discard this local preview.") + form("branding",
        '<div class="branding-preview wide"><p class="eyebrow">Your community, in good company</p><h3 data-branding-title>' + e(branding.name || branding.site_name || "LibraryShare") + '</h3><p>Useful things. Generous neighbors. A welcoming place to share.</p><span class="status-pill">Appearance preview</span><p class="form-hint" data-branding-status role="status">Showing saved settings. Changes stay in this browser until you save.</p></div>' +
        field("Color theme (replaces the four colors below)","theme_preset",branding.theme_preset,"select",{choices:[["sunny","Sunny — cream & coral"],["ocean","Ocean — sea glass & clay"],["forest","Forest — sage & rust"]]}) +
        field("Typography","font_style",branding.font_style,"select",{choices:[["friendly","Friendly"],["classic","Classic"],["system","System"]]}) +
        field("Corners","corner_style",branding.corner_style,"select",{choices:[["rounded","Rounded"],["square","Square"]]}) +
        field("Spacing","density",branding.density,"select",{choices:[["comfortable","Comfortable"],["compact","Compact"]]}) +
        '<p class="form-hint wide">Choosing a theme fills the color fields. Adjust any color afterward for your library. Existing custom colors are preserved when opening this page.</p>' +
        field("Service name","name",branding.name || branding.site_name,"text",{required:true,maxlength:120}) +
        field("Site / browser title","site_name",branding.site_name,"text",{maxlength:120}) +
        field("Tagline","tagline",branding.tagline,"text",{maxlength:200,wide:true}) +
        field("Logo URL","logo_url",branding.logo_url,"text",{maxlength:2000}) +
        field("Favicon URL","favicon_url",branding.favicon_url,"text",{maxlength:2000}) +
        field("Primary color","primary_color",branding.primary_color,"color") +
        field("Accent color","accent_color",branding.accent_color,"color") +
        field("Page background","background_color",branding.background_color,"color") +
        field("Foreground / text","foreground_color",branding.foreground_color,"color") +
        field("Homepage headline","homepage_hero_title",branding.homepage_hero_title,"textarea",{wide:true,maxlength:2000}) +
        field("Homepage introduction","homepage_hero_body",branding.homepage_hero_body,"textarea",{wide:true,maxlength:2000}) +
        field("Footer text","footer_text",branding.footer_text,"text",{wide:true,maxlength:2000}) +
        field("Public Koha URL","koha_public_url",branding.koha_public_url,"text",{maxlength:2000}) +
        field("Library website URL","library_website_url",branding.library_website_url,"text",{maxlength:2000}) +
        field("Custom CSS (trusted administrators only)","custom_css",branding.custom_css,"textarea",{wide:true,maxlength:20000}) +
        '<p class="form-hint wide">Custom CSS takes precedence over design controls. Asset and destination URLs must use HTTPS or a same-origin HTTP(S) URL/path; external assets may contact third parties. Leave optional fields empty to use LibraryShare defaults. Logo images should remain legible at 42 pixels.</p>' +
        '<div class="branding-actions wide">' + button("Cancel preview","staff-branding-cancel") + button("Reset to saved","staff-branding-reset") + '</div>');
    }
    if(section==="legal"){
      var docs=config.documents || [];
      return header("Legal documents & help","Publishing a new required version asks members to accept it before they lend or borrow.") + '<p class="audit-note">Change the version whenever the text or requirements change. Published text is displayed as plain text, not executable HTML.</p>' + docs.map(function(d){return '<article class="document"><p class="eyebrow">' + e(d.document_key) + ' · ' + e(d.version) + ' · ' + (n(d.required) ? 'required' : 'optional') + '</p><h3>' + e(d.title) + '</h3><p class="document-body">' + e(d.body) + '</p>' + button("Edit document","staff-document",d.document_key) + '</article>';}).join("") + button("Publish / update a document","staff-document","");
    }
    if(section==="settings"){
      var s=config.settings || {};
      var additional=[
        ["credits_per_kudos","Credits per thank-you note"],["credits_first_listing","Credits for a first listing"],["credits_per_on_time_return","Credits per on-time return"],["credits_wanted_fulfilled","Credits per wish fulfilled"],
        ["priority_threshold","Priority credit threshold"],["longer_loan_threshold","Longer-loan credit threshold"],["longer_loan_bonus_days","Longer-loan bonus days"],["fast_track_min_on_time","On-time returns for fast track"]
      ];
      return header("Circulation & incentives","LibraryShare uses local Koha circulation. No remote Koha credentials are needed.") + '<p class="audit-note">Create the dedicated item type in Koha first. Existing checkouts keep their original due dates. Disabling gamification does not remove circulation history.</p>' +
        form("settings",
          field("Koha item type code","item_type_code",s.item_type_code || "PEERLEND","text",{required:true,maxlength:10}) +
          field("Default loan days","default_loan_days",s.default_loan_days == null ? 14 : s.default_loan_days,"number",{min:1,max:90,required:true}) +
          field("Enable gamification","gamification_enabled",s.gamification_enabled,"checkbox",{wide:true}) +
          field("Credits per completed loan","credits_per_completed_loan",s.credits_per_completed_loan,"number",{min:0,max:100,required:true}) +
          field("Borrow credit cost","borrow_credit_cost",s.borrow_credit_cost,"number",{min:0,required:true}) +
          field("Starting credits","starting_credits",s.starting_credits,"number",{min:0,required:true}) +
          field("Maximum active requests","max_active_requests",s.max_active_requests,"number",{min:1,required:true}) +
          field("Featured lender (patron number, 0 clears)","featured_lender",s.featured_lender || 0,"number",{min:0}) +
          field("Community goal (completed loans)","community_goal",s.community_goal || 0,"number",{min:0}) +
          field("Loan milestone","milestone_loans",s.milestone_loans || 0,"number",{min:0}) +
          additional.filter(function(pair){return Object.prototype.hasOwnProperty.call(s,pair[0]);}).map(function(pair){return field(pair[1],pair[0],s[pair[0]],"number",{min:0,max:1000000,required:true});}).join("")
        ) + '<p class="form-hint">Credit awards, borrowing checks, challenge progress, and badges are calculated on the server. Community estimates are managed in Impact &amp; analytics.</p>';
    }
    if(section==="challenges"){
      var challenges=data.challenges || catalogs.challenges || [];
      return header("Community challenges","Use specific goals and a date window. Progress is derived from recorded activity.") + button("Create challenge","staff-challenge","") + X.table("Challenges",challenges,[["Title","title"],["Goal","goal"],["Starts","start_date"],["Ends","end_date"],["Active",function(r){return n(r.active) ? "Yes" : "No";}],["Actions",function(r){return button("Edit","staff-challenge",r.id) + button("Delete","staff-delete-challenge",r.id);}]]);
    }
    if(section==="badges")return header("Badge catalog","Configure custom recognition using a measured activity and threshold.") + button("Create badge","staff-badge","") + X.table("Badges",catalogs.badges || [],[["Key","slug"],["Label","label"],["Description","description"],["Family","family"],["Metric","metric"],["Threshold","threshold"],["Active",function(r){return n(r.active) ? "Yes" : "No";}],["Actions",function(r){return button("Edit","staff-badge",r.slug) + button("Delete","staff-delete-badge",r.slug);}]]) + X.table("Recognition levels",catalogs.levels || [],[["Family","family"],["Level",function(r){return e(r.label || r.level);}],["Threshold",function(r){return e(r.threshold == null ? r.loans : r.threshold);}]]) + '<p class="form-hint">Badge image upload and remote badge images are not available in the Koha API contract. Badges use the built-in medal treatment.</p>';
    if(section==="impact"){
      var totals=catalogs.totals || {};
      return header("Savings & analytics","Savings are 50% of each item’s current estimated value per completed loan, rounded to cents. Owners edit the value on their listing; edits recalculate past savings. Loans without an item value are excluded from savings totals.") + '<div class="stats-row">' + [["Loans",totals.loans],["Estimated value saved ($)",Number(totals.value_saved || 0).toFixed(2)],["Loans without item value",totals.unvalued_loans]].map(function(pair){return '<div class="stat"><strong class="number">' + e(pair[1] == null ? 0 : pair[1]) + '</strong><span>' + e(pair[0]) + '</span></div>';}).join("") + '</div>' +
        X.table("Monthly circulation",catalogs.monthly || [],[["Month","month"],["Loans","loans"]]) + X.table("Category outcomes",catalogs.categories || [],[["Category","category"],["Loans","loans"],["Estimated value saved ($)","value_saved"],["Loans without item value","unvalued_loans"]]) + X.table("Branch circulation",catalogs.branches || [],[["Branch","branchcode"],["Loans","loans"]]);
    }
    if(section==="credits")return header("Credits & recompute","Adjust an account with an explanation, or reconcile statistics against source circulation.") + form("credits",field("Koha patron number","patron_id","","number",{min:1,required:true}) + field("Credit change (negative deducts)","delta","","number",{required:true}) + field("Adjustment note","note","","textarea",{required:true,wide:true,maxlength:1000})) +
      '<div class="panel"><h3>Recompute from source</h3><p class="form-hint">Recalculate statistics and awards from real lending history without awarding duplicate credits. This is not a data reset.</p>' + button("Recompute statistics & awards","staff-recompute") + '</div><p class="audit-note">Production demo reset and destructive snapshots are intentionally excluded: they could destroy real Koha circulation records. Use safe fixture tests in a non-production environment.</p>';
    if(section==="audit")return header("Moderation audit","Reasons and actors are retained for accountability.") + X.table("Audit trail",data.audit || [],[["When","created_at"],["Actor",function(r){return e(r.actor_borrowernumber || r.actor);}],["Record",function(r){return e(r.target || r.entity_id || r.target_id || r.id);}],["Action","action"],["Reason",function(r){return e(r.reason || r.note);}]]);
    if(section==="diagnostics"){
      var d=catalogs,item=d.item_type || {},media=d.media || {};
      return header("Koha diagnostics","Read-only installation checks. These do not create or reset circulation data.") + X.table("Installation status",[
        {check:"Database",value:d.database},
        {check:"Item type",value:(item.code || "Not configured") + " · " + (item.exists ? "exists" : "missing")},
        {check:"Photo storage",value:(media.configured ? "configured" : "not configured") + " · " + (media.writable ? "writable" : "not writable")},
        {check:"Koha version",value:d.koha_version},
        {check:"API namespace",value:d.route_namespace}
      ],[["Check","check"],["Result","value"]]) + '<p class="form-hint">Create the configured item type and verify the Koha upload directory is writable if those checks fail. No credentials are displayed here.</p><div class="toolbar"><a class="button button-light" href="/cgi-bin/koha/admin/itemtypes.pl">Manage Koha item types</a>' + button("Run checks again","staff-section","diagnostics") + '</div>';
    }
    return X.empty("Choose a staff section.");
  }
  function moderationForm(el){
    var entity=el.dataset.entity, operation=el.dataset.operation;
    X.modal((operation==="grant" || operation==="revoke" ? "Change member role" : "Moderate " + entity),
      '<p class="audit-note">' + (operation==="remove" && entity!=="listing" ? "This permanently deletes the " + e(entity) + ". It cannot be restored." : entity==="role" ? "This changes the LibraryShare admin role only. Koha plugin-management permission is required." : "Listing moderation preserves the Koha catalog and circulation records.") + '</p>' +
      form("moderate",'<input type="hidden" name="entity" value="' + e(entity) + '"><input type="hidden" name="action" value="' + e(operation) + '">' + field("Reason for " + operation,"reason","","textarea",{required:true,wide:true,maxlength:1000}),el.dataset.id));
  }
  function documentForm(key){
    var d=(config.documents || []).find(function(row){return row.document_key===key;}) || {};
    X.modal("Publish library document",form("document",field("Document","document_key",d.document_key || "terms","select",{choices:[["terms","Terms of sharing"],["waiver","Lending waiver"],["help","Help"]],required:true}) + field("Title","title",d.title,"text",{required:true,maxlength:200}) + field("Version","version",d.version,"text",{required:true,maxlength:80}) + field("Require acceptance","required",d.required,"checkbox") + field("Document text","body",d.body,"textarea",{wide:true,required:true})));
  }
  function challengeForm(id){
    var c=(data.challenges || catalogs.challenges || []).find(function(row){return n(row.id)===n(id);}) || {};
    X.modal(id ? "Edit challenge" : "Create community challenge",form("challenge",
      field("Title","title",c.title,"text",{required:true,maxlength:200}) + field("Goal (completed loans)","goal",c.goal == null ? "" : c.goal,"number",{required:true,min:1}) +
      field("Start date","start_date",String(c.start_date || "").slice(0,10),"date",{required:true}) + field("End date","end_date",String(c.end_date || "").slice(0,10),"date",{required:true}) +
      field("Description","description",c.description,"textarea",{wide:true,required:true,maxlength:2000}) + field("Active","active",c.active == null ? true : c.active,"checkbox",{wide:true}),id));
  }
  function badgeForm(slug){
    var badge=(catalogs.badges || []).find(function(row){return row.slug===slug;}) || {};
    X.modal(slug ? "Edit recognition badge" : "Create recognition badge",form("badge",
      field("Badge key (letters, digits, underscores)","slug",badge.slug,"text",{required:true,maxlength:80}) +
      field("Label","label",badge.label,"text",{required:true,maxlength:120}) +
      field("Family","family",badge.family || "lender","select",{choices:["lender","borrower","community"],required:true}) +
      field("Metric","metric",badge.metric || "loans_as_lender","select",{choices:["loans_as_lender","loans_as_borrower","distinct_items_lent","distinct_categories_lent","kudos_count","streak_months_lender","avg_rating_lender","on_time_returns","perfect_streak","category_specialist","longest_loan_days","community_pillar","careful_custodian","wishes_fulfilled","distinct_categories_borrowed"],required:true}) +
      field("Threshold","threshold",badge.threshold,"number",{required:true,min:0,step:"any"}) + field("Active","active",badge.active == null ? true : badge.active,"checkbox") +
      field("Description","description",badge.description,"textarea",{required:true,wide:true,maxlength:2000}),slug));
  }
  S.action=async function(action,el){
    if(action.indexOf("staff-")!==0)return false;
    B=X.context;
    try{
      if(action==="staff-branding-reset" || action==="staff-branding-cancel")restoreBranding();
      else if(action==="staff-section")await load(el.dataset.id);
      else if(action==="staff-retry")await load(current);
      else if(action==="staff-moderate")moderationForm(el);
      else if(action==="staff-report")X.modal("Review member report",form("report",'<input type="hidden" name="status" value="' + e(el.dataset.status) + '">' + field("Resolution note","note","","textarea",{required:true,wide:true,maxlength:2000}),el.dataset.id));
      else if(action==="staff-document")documentForm(el.dataset.id);
      else if(action==="staff-challenge")challengeForm(el.dataset.id);
      else if(action==="staff-badge")badgeForm(el.dataset.id);
      else if(action==="staff-delete-challenge" || action==="staff-delete-badge"){
        X.modal("Delete " + (action==="staff-delete-badge" ? "badge" : "challenge") + "?",
          '<p class="audit-note">This permanently deletes this configuration record. Confirm the selected key before continuing: ' + e(el.dataset.id) + '.</p>' +
          form(action==="staff-delete-badge" ? "delete-badge" : "delete-challenge",field("I understand this deletion cannot be undone","confirm",false,"checkbox",{required:true,wide:true}),el.dataset.id));
      }
      else if(action==="staff-recompute")X.modal("Recompute statistics & awards",'<p class="audit-note">Rebuild from source circulation records. Existing credits are not duplicated. This operation does not reset or delete circulation history.</p>' + form("recompute",field("I want to reconcile community statistics","confirm",false,"checkbox",{required:true,wide:true})));
      return true;
    }catch(error){X.dialogError(error);return true;}
  };
  S.submit=async function(formElement){
    B=X.context;
    var kind=formElement.dataset.staff, values=B.form(formElement), id=formElement.dataset.id, submitter=formElement.querySelector('[type="submit"]');
    if(!kind)return false;
    if(submitter)submitter.disabled=true;
    try {
      if(kind==="moderate")await X.ext("admin",{entity:values.entity,id:n(id),action:values.action,reason:values.reason});
      else if(kind==="role")await X.ext("admin",{entity:"role",id:n(values.patron_id),action:values.action,reason:values.reason});
      else if(kind==="report")await X.ext("reports",{id:n(id),status:values.status,note:values.note});
      else if(kind==="branding"){
        ["logo_url","favicon_url","koha_public_url","library_website_url"].forEach(function(key){
          if(!values[key])return;
          var safe=X.safeBrandUrl(values[key]);
          if(!safe)throw new Error("Use HTTPS or a same-origin URL for " + key.replace(/_/g," ") + ".");
          var parsed=new URL(safe,location.href);
          values[key]=parsed.origin===location.origin ? parsed.pathname+parsed.search+parsed.hash : safe;
        });
        await X.ext("config",{branding:values});
        config.branding=Object.assign({},values);
      }
      else if(kind==="document"){values.required=formElement.elements.required.checked;await X.ext("documents",values);}
      else if(kind==="settings"){
        Object.keys(values).forEach(function(key){if(key!=="item_type_code")values[key]=n(values[key]);});
        values.gamification_enabled=formElement.elements.gamification_enabled.checked ? 1 : 0;
        await X.ext("config",{settings:values});
      }
      else if(kind==="challenge"){
        if(values.end_date < values.start_date)throw new Error("The challenge end date cannot be before the start date.");
        values.goal=n(values.goal);values.active=formElement.elements.active.checked;if(id)values.id=n(id);await X.ext("challenges",values);
      }
      else if(kind==="delete-challenge")await X.ext("challenges",{id:n(id),remove:true});
      else if(kind==="badge"){
        if(!/^[a-z0-9_]+$/i.test(values.slug))throw new Error("Badge keys can contain only letters, digits and underscores.");
        if(id && values.slug!==id)throw new Error("Keep the existing key when editing. Create a new badge to use a different key.");
        values.threshold=n(values.threshold);values.active=formElement.elements.active.checked;await X.ext("badges",values);
      }
      else if(kind==="delete-badge")await X.ext("badges",{slug:id,remove:true});
      else if(kind==="credits"){await X.ext("credits",{patron_id:n(values.patron_id),delta:n(values.delta),note:values.note});formElement.reset();}
      else if(kind==="recompute")await X.ext("credits",{recompute:true});
      X.close();B.notice(kind==="recompute" ? "Statistics and awards recomputed without duplicating credits." : "Changes saved.");
      if(kind==="branding"){
        X.applyBranding(values);
      }
      await load(current);return true;
    }catch(error){X.dialogError(error);return true;}
    finally{if(submitter)submitter.disabled=false;}
  };
})();

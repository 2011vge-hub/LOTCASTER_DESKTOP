const state = {
  auth: null,
  settings: null,
  team: { users: [], activity: [], totals: {} },
  store: { vehicles: [], removed: [] },
  queueFocus: null,
  installPrompt: null
};

const els = {
  authScreen: document.querySelector("#authScreen"),
  authForm: document.querySelector("#authForm"),
  authTitle: document.querySelector("#authTitle"),
  authIntro: document.querySelector("#authIntro"),
  ownerNameLabel: document.querySelector("#ownerNameLabel"),
  authName: document.querySelector("#authName"),
  authEmail: document.querySelector("#authEmail"),
  authPassword: document.querySelector("#authPassword"),
  authRememberDevice: document.querySelector("#authRememberDevice"),
  rememberDeviceLabel: document.querySelector("#rememberDeviceLabel"),
  forgotPasswordButton: document.querySelector("#forgotPasswordButton"),
  togglePasswordButton: document.querySelector("#togglePasswordButton"),
  authSubmit: document.querySelector("#authSubmit"),
  authMessage: document.querySelector("#authMessage"),
  appShell: document.querySelector("#appShell"),
  accountName: document.querySelector("#accountName"),
  licenseStatus: document.querySelector("#licenseStatus"),
  logoutButton: document.querySelector("#logoutButton"),
  inventoryTab: document.querySelector("#inventoryTab"),
  postingTab: document.querySelector("#postingTab"),
  teamTab: document.querySelector("#teamTab"),
  helpTab: document.querySelector("#helpTab"),
  accessTab: document.querySelector("#accessTab"),
  inventoryView: document.querySelector("#inventoryView"),
  inventoryControls: document.querySelector("#inventoryControls"),
  postingView: document.querySelector("#postingView"),
  teamView: document.querySelector("#teamView"),
  helpView: document.querySelector("#helpView"),
  accessView: document.querySelector("#accessView"),
  dealerForm: document.querySelector("#dealerForm"),
  dealerName: document.querySelector("#dealerName"),
  dealerEmail: document.querySelector("#dealerEmail"),
  dealerPlan: document.querySelector("#dealerPlan"),
  dealerExpiresAt: document.querySelector("#dealerExpiresAt"),
  dealerNotes: document.querySelector("#dealerNotes"),
  accessStatus: document.querySelector("#accessStatus"),
  dealerList: document.querySelector("#dealerList"),
  teamUserForm: document.querySelector("#teamUserForm"),
  teamUserName: document.querySelector("#teamUserName"),
  teamUserEmail: document.querySelector("#teamUserEmail"),
  teamUserRole: document.querySelector("#teamUserRole"),
  teamPasswordField: document.querySelector("#teamPasswordField"),
  teamUserPassword: document.querySelector("#teamUserPassword"),
  teamStatus: document.querySelector("#teamStatus"),
  teamMemberList: document.querySelector("#teamMemberList"),
  teamActivityList: document.querySelector("#teamActivityList"),
  teamAssignedCount: document.querySelector("#teamAssignedCount"),
  teamPreparedCount: document.querySelector("#teamPreparedCount"),
  teamPostedCount: document.querySelector("#teamPostedCount"),
  teamUnassignedCount: document.querySelector("#teamUnassignedCount"),
  inventoryUrl: document.querySelector("#inventoryUrl"),
  docFee: document.querySelector("#docFee"),
  sourcePriceIncludesDocFee: document.querySelector("#sourcePriceIncludesDocFee"),
  dealershipName: document.querySelector("#dealershipName"),
  city: document.querySelector("#city"),
  listingFooter: document.querySelector("#listingFooter"),
  sourceNote: document.querySelector("#sourceNote"),
  walkerSourceButton: document.querySelector("#walkerSourceButton"),
  saveSourceButton: document.querySelector("#saveSourceButton"),
  importText: document.querySelector("#importText"),
  importFile: document.querySelector("#importFile"),
  autoImportButton: document.querySelector("#autoImportButton"),
  scrapeButton: document.querySelector("#scrapeButton"),
  autoCsvLink: document.querySelector("#autoCsvLink"),
  openInventoryLink: document.querySelector("#openInventoryLink"),
  manualButton: document.querySelector("#manualButton"),
  manualTitle: document.querySelector("#manualTitle"),
  manualPrice: document.querySelector("#manualPrice"),
  manualMileage: document.querySelector("#manualMileage"),
  manualVin: document.querySelector("#manualVin"),
  manualStock: document.querySelector("#manualStock"),
  manualUrl: document.querySelector("#manualUrl"),
  manualImage: document.querySelector("#manualImage"),
  manualBodyType: document.querySelector("#manualBodyType"),
  importButton: document.querySelector("#importButton"),
  pageImportButton: document.querySelector("#pageImportButton"),
  exportLink: document.querySelector('a[href="/api/export.csv"]'),
  vehicleCount: document.querySelector("#vehicleCount"),
  newCount: document.querySelector("#newCount"),
  removedCount: document.querySelector("#removedCount"),
  postedCount: document.querySelector("#postedCount"),
  searchInput: document.querySelector("#searchInput"),
  statusFilter: document.querySelector("#statusFilter"),
  statusMessage: document.querySelector("#statusMessage"),
  vehicleGrid: document.querySelector("#vehicleGrid"),
  postingSourceBadge: document.querySelector("#postingSourceBadge"),
  queueUnassignedCard: document.querySelector("#queueUnassignedCard"),
  queuePrepCard: document.querySelector("#queuePrepCard"),
  queueReadyCard: document.querySelector("#queueReadyCard"),
  queuePostedCard: document.querySelector("#queuePostedCard"),
  queueOverdueCard: document.querySelector("#queueOverdueCard"),
  queueUnassignedCount: document.querySelector("#queueUnassignedCount"),
  queuePrepCount: document.querySelector("#queuePrepCount"),
  queueReadyCount: document.querySelector("#queueReadyCount"),
  queuePostedCount: document.querySelector("#queuePostedCount"),
  queueOverdueCount: document.querySelector("#queueOverdueCount"),
  postingQueueList: document.querySelector("#postingQueueList"),
  postingPeopleList: document.querySelector("#postingPeopleList"),
  template: document.querySelector("#vehicleTemplate"),
  installButton: document.querySelector("#installButton"),
  facebookDialog: document.querySelector("#facebookDialog"),
  postingTitle: document.querySelector("#postingTitle"),
  postingFields: document.querySelector("#postingFields"),
  postingPhotos: document.querySelector("#postingPhotos"),
  requiredChecklist: document.querySelector("#requiredChecklist"),
  postingBodyType: document.querySelector("#postingBodyType"),
  postingBodyStyle: document.querySelector("#postingBodyStyle"),
  postingExteriorColor: document.querySelector("#postingExteriorColor"),
  postingInteriorColor: document.querySelector("#postingInteriorColor"),
  postingFuelType: document.querySelector("#postingFuelType"),
  saveBodyTypeButton: document.querySelector("#saveBodyTypeButton"),
  postingDescription: document.querySelector("#postingDescription"),
  postingPhotoLink: document.querySelector("#postingPhotoLink"),
  copyPostingButton: document.querySelector("#copyPostingButton"),
  copyPacketButton: document.querySelector("#copyPacketButton"),
  closePostingButton: document.querySelector("#closePostingButton"),
  openFacebookButton: document.querySelector("#openFacebookButton"),
  facebookHelperStatus: document.querySelector("#facebookHelperStatus"),
  checkHelperButton: document.querySelector("#checkHelperButton")
};

init();

async function init() {
  bindEvents();
  await completeEmailAuthLink();
  await loadAuth();
  registerServiceWorker();
}

async function completeEmailAuthLink() {
  const params = new URLSearchParams(window.location.hash.replace(/^#/, ""));
  const accessToken = params.get("access_token");
  const refreshToken = params.get("refresh_token");
  const linkType = params.get("type");
  if (!accessToken || !refreshToken || !["invite", "recovery", "signup"].includes(linkType)) return;
  let newPassword = "";
  if (linkType === "invite" || linkType === "recovery") {
    newPassword = window.prompt("Create your LotCaster password. Use at least 10 characters.") || "";
    if (newPassword.length < 10) {
      window.history.replaceState({}, document.title, window.location.pathname);
      state.auth = { setupRequired: false, authenticated: false, hosted: true };
      showAuth();
      els.authMessage.textContent = "The email link was valid, but a password of at least 10 characters is required. Request another link when ready.";
      return;
    }
  }
  try {
    state.auth = await api("/api/auth/complete-link", {
      method: "POST",
      body: JSON.stringify({
        accessToken,
        refreshToken,
        expiresIn: Number(params.get("expires_in")) || 3600,
        type: linkType,
        password: newPassword,
        rememberDevice: true
      })
    });
  } catch (error) {
    state.auth = { setupRequired: false, authenticated: false, hosted: true };
    showAuth();
    els.authMessage.textContent = error.message || "This email link could not be completed. Request a new link.";
  } finally {
    window.history.replaceState({}, document.title, window.location.pathname);
  }
}

function bindEvents() {
  els.authForm.addEventListener("submit", submitAuth);
  els.togglePasswordButton.addEventListener("click", () => {
    const showing = els.authPassword.type === "text";
    els.authPassword.type = showing ? "password" : "text";
    els.togglePasswordButton.textContent = showing ? "Show" : "Hide";
  });
  els.forgotPasswordButton.addEventListener("click", recoverPassword);
  els.logoutButton.addEventListener("click", logout);
  els.inventoryTab.addEventListener("click", () => {
    state.queueFocus = null;
    showWorkspace("inventory");
  });
  els.postingTab.addEventListener("click", () => showWorkspace("posting"));
  els.teamTab.addEventListener("click", () => showWorkspace("team"));
  els.helpTab.addEventListener("click", () => showWorkspace("help"));
  els.accessTab.addEventListener("click", () => showWorkspace("access"));
  els.dealerForm.addEventListener("submit", addDealer);
  els.teamUserForm.addEventListener("submit", addTeamUser);
  els.walkerSourceButton.addEventListener("click", useWalkerSource);
  els.saveSourceButton.addEventListener("click", saveSettingsOnly);
  els.autoImportButton.addEventListener("click", autoImportInventory);
  els.scrapeButton.addEventListener("click", refreshInventory);
  els.manualButton.addEventListener("click", saveManualVehicle);
  els.importButton.addEventListener("click", importInventory);
  els.pageImportButton.addEventListener("click", importPastedPage);
  els.searchInput.addEventListener("input", render);
  els.statusFilter.addEventListener("change", () => {
    state.queueFocus = null;
    render();
  });
  els.queueUnassignedCard.addEventListener("click", () => openInventoryFilter("active", "unassigned"));
  els.queuePrepCard.addEventListener("click", () => openInventoryFilter("unposted", "needs details"));
  els.queueReadyCard.addEventListener("click", () => openInventoryFilter("unposted", "ready to post"));
  els.queuePostedCard.addEventListener("click", () => openInventoryFilter("posted", "posted"));
  els.queueOverdueCard.addEventListener("click", () => openInventoryFilter("active", "overdue"));
  els.inventoryUrl.addEventListener("input", () => {
    els.openInventoryLink.href = els.inventoryUrl.value || "#";
    updateSourceNote();
  });
  els.closePostingButton.addEventListener("click", () => els.facebookDialog.close());
  els.facebookDialog.addEventListener("click", (event) => {
    if (event.target === els.facebookDialog) els.facebookDialog.close();
  });
  els.copyPostingButton.addEventListener("click", async () => {
    await copyText(els.postingDescription.value);
    showTemporaryButtonText(els.copyPostingButton, "Copied", "Copy Description");
  });
  els.copyPacketButton.addEventListener("click", async () => {
    const vehicle = selectedPacketVehicle();
    if (!vehicle) return;
    await copyText(buildFullListingPacket(vehicle, els.postingDescription.value));
    showTemporaryButtonText(els.copyPacketButton, "Copied", "Copy Full Listing Packet");
  });
  els.saveBodyTypeButton.addEventListener("click", saveVehicleBodyType);
  els.postingDescription.addEventListener("input", () => {
    const vehicle = selectedPacketVehicle();
    if (vehicle) renderRequiredChecklist(vehicle, els.postingDescription.value);
  });
  els.openFacebookButton.addEventListener("click", openFacebookWithVehicle);
  els.checkHelperButton.addEventListener("click", checkHelperConnection);
  window.addEventListener("message", (event) => {
    if (event.source !== window || event.data?.type !== "walker-facebook-helper-ready") return;
    document.documentElement.dataset.walkerFacebookHelper = event.data.version;
    updateHelperStatus();
  });
  els.installButton.addEventListener("click", async () => {
    if (!state.installPrompt) return;
    state.installPrompt.prompt();
    await state.installPrompt.userChoice;
    state.installPrompt = null;
    els.installButton.hidden = true;
  });
  window.addEventListener("beforeinstallprompt", (event) => {
    event.preventDefault();
    state.installPrompt = event;
    els.installButton.hidden = false;
  });
}

async function loadAuth() {
  try {
    state.auth = await api("/api/auth/status");
    if (state.auth.authenticated) {
      await enterApp();
    } else {
      showAuth();
    }
  } catch (error) {
    els.authMessage.textContent = error.message || "Could not check account status.";
  }
}

function showAuth() {
  const setup = Boolean(state.auth?.setupRequired);
  els.appShell.hidden = true;
  els.authScreen.hidden = false;
  els.ownerNameLabel.hidden = !setup;
  els.authTitle.textContent = setup ? "Create Owner Account" : "Sign In";
  els.authIntro.textContent = setup
    ? "Secure this installation and begin its 30-day internal trial."
    : "Sign in to access dealership inventory and exports.";
  els.authSubmit.textContent = setup ? "Create Owner Account" : "Sign In";
  els.authPassword.autocomplete = setup ? "new-password" : "current-password";
  els.authPassword.minLength = setup ? 10 : 1;
  els.forgotPasswordButton.hidden = setup;
  if (!setup && state.auth?.loginEmail) els.authEmail.value = state.auth.loginEmail;
  els.authMessage.textContent = "";
}

async function submitAuth(event) {
  event.preventDefault();
  const setup = Boolean(state.auth?.setupRequired);
  els.authSubmit.disabled = true;
  els.authMessage.textContent = setup ? "Creating secure owner account..." : "Signing in...";
  try {
    state.auth = await api(setup ? "/api/auth/setup" : "/api/auth/login", {
      method: "POST",
      body: JSON.stringify({
        name: els.authName.value,
        email: els.authEmail.value,
        password: els.authPassword.value,
        rememberDevice: els.authRememberDevice.checked
      })
    });
    els.authPassword.value = "";
    if (!state.auth.authenticated) {
      showAuth();
      els.authMessage.textContent = state.auth.message || "Check your email to finish signing in.";
      return;
    }
    await enterApp();
  } catch (error) {
    els.authMessage.textContent = error.message || "Authentication failed.";
  } finally {
    els.authSubmit.disabled = false;
  }
}

async function recoverPassword() {
  const email = els.authEmail.value.trim();
  if (!email) {
    els.authMessage.textContent = "Enter your email address first.";
    els.authEmail.focus();
    return;
  }
  els.forgotPasswordButton.disabled = true;
  try {
    const result = await api("/api/auth/recover", {
      method: "POST",
      body: JSON.stringify({ email })
    });
    els.authMessage.textContent = result.message;
  } catch (error) {
    els.authMessage.textContent = error.message || "Password recovery could not be started.";
  } finally {
    els.forgotPasswordButton.disabled = false;
  }
}

function roleLabel(role) {
  return ({
    master: "LotCaster Master",
    lotcaster_general_manager: "LotCaster General Manager",
    lotcaster_manager: "LotCaster Manager",
    lotcaster_support: "LotCaster Support",
    owner: "Dealer Owner",
    manager: "Dealership Manager",
    salesperson: "Salesperson"
  })[role] || role;
}

async function enterApp() {
  els.authScreen.hidden = true;
  els.appShell.hidden = false;
  els.accountName.textContent = `${state.auth.user.name} | ${roleLabel(state.auth.user.role)}`;
  const expires = state.auth.license?.expiresAt ? formatDate(state.auth.license.expiresAt) : "No expiration";
  els.licenseStatus.textContent = `${state.auth.license?.plan || "Internal"} ${state.auth.license?.status || "license"} | ${expires}`;
  const master = ["master", "lotcaster_general_manager"].includes(state.auth.user.role);
  const manager = ["master", "lotcaster_general_manager", "lotcaster_manager", "lotcaster_support", "owner", "manager"].includes(state.auth.user.role);
  els.accessTab.hidden = !master;
  els.teamTab.hidden = !manager;
  els.inventoryControls.hidden = state.auth.user.role === "salesperson";
  els.teamPasswordField.hidden = Boolean(state.auth.hosted);
  els.teamUserPassword.required = !state.auth.hosted;
  els.teamUserPassword.disabled = Boolean(state.auth.hosted);
  if (state.auth.user.role === "manager") {
    els.teamUserRole.value = "salesperson";
    els.teamUserRole.disabled = true;
  } else {
    els.teamUserRole.disabled = false;
  }
  showWorkspace("inventory");
  await Promise.all([loadSettings(), loadInventory(), manager ? loadTeam() : Promise.resolve()]);
  render();
  if (sessionStorage.getItem("lotcasterResumeRefresh") === "1") {
    sessionStorage.removeItem("lotcasterResumeRefresh");
    window.setTimeout(refreshInventory, 0);
  } else if (manager && sessionStorage.getItem("lotcasterOpeningRefresh") !== "1") {
    sessionStorage.setItem("lotcasterOpeningRefresh", "1");
    window.setTimeout(refreshInventory, 250);
  }
}

async function showWorkspace(view) {
  const master = ["master", "lotcaster_general_manager"].includes(state.auth?.user?.role);
  const manager = ["master", "lotcaster_general_manager", "lotcaster_manager", "lotcaster_support", "owner", "manager"].includes(state.auth?.user?.role);
  const access = view === "access" && master;
  const team = view === "team" && manager;
  const posting = view === "posting";
  const help = view === "help";
  els.inventoryView.hidden = access || help || team || posting;
  els.postingView.hidden = !posting;
  els.teamView.hidden = !team;
  els.helpView.hidden = !help;
  els.accessView.hidden = !access;
  els.inventoryTab.classList.toggle("active", !access && !help && !team && !posting);
  els.postingTab.classList.toggle("active", posting);
  els.teamTab.classList.toggle("active", team);
  els.helpTab.classList.toggle("active", help);
  els.accessTab.classList.toggle("active", access);
  if (access) await loadDealers();
  if (team) await loadTeam();
  if (posting) {
    if (manager) await loadTeam();
    renderPostingCenter();
  }
}

async function loadDealers() {
  try {
    const registry = await api("/api/admin/dealers");
    renderDealers(registry.dealers || []);
    els.accessStatus.textContent = `${(registry.dealers || []).length} dealer accounts registered.`;
  } catch (error) {
    els.accessStatus.textContent = error.message || "Could not load dealer access.";
  }
}

async function addDealer(event) {
  event.preventDefault();
  try {
    const registry = await api("/api/admin/dealers", {
      method: "POST",
      body: JSON.stringify({
        name: els.dealerName.value,
        ownerEmail: els.dealerEmail.value,
        plan: els.dealerPlan.value,
        expiresAt: els.dealerExpiresAt.value || null,
        notes: els.dealerNotes.value
      })
    });
    els.dealerForm.reset();
    renderDealers(registry.dealers || []);
    els.accessStatus.textContent = "Dealer access record added.";
  } catch (error) {
    els.accessStatus.textContent = error.message || "Could not add dealer.";
  }
}

function renderDealers(dealers) {
  els.dealerList.replaceChildren(...dealers.map((dealer) => {
    const row = document.createElement("article");
    row.className = "dealer-row";
    const details = document.createElement("div");
    const title = document.createElement("strong");
    const meta = document.createElement("small");
    const notes = document.createElement("p");
    const status = document.createElement("span");
    const toggle = document.createElement("button");
    title.textContent = dealer.name;
    meta.textContent = `${dealer.ownerEmail} | ${dealer.plan} | ${dealer.expiresAt ? `expires ${formatDate(dealer.expiresAt)}` : "no expiration"}`;
    notes.textContent = dealer.notes || "No notes";
    status.textContent = dealer.status;
    status.className = `dealer-status ${dealer.status}`;
    toggle.type = "button";
    toggle.className = dealer.status === "active" ? "suspend-button" : "activate-button";
    toggle.textContent = dealer.status === "active" ? "Suspend Access" : "Restore Access";
    toggle.addEventListener("click", () => setDealerStatus(dealer, dealer.status === "active" ? "suspended" : "active"));
    details.append(title, meta, notes);
    row.append(details, status, toggle);
    return row;
  }));
}

async function setDealerStatus(dealer, status) {
  try {
    const registry = await api("/api/admin/dealer-status", {
      method: "POST",
      body: JSON.stringify({ id: dealer.id, status })
    });
    renderDealers(registry.dealers || []);
    els.accessStatus.textContent = `${dealer.name} access ${status === "suspended" ? "suspended" : "restored"}.`;
  } catch (error) {
    els.accessStatus.textContent = error.message || "Could not update dealer access.";
  }
}

async function loadTeam() {
  if (!["master", "lotcaster_general_manager", "lotcaster_manager", "lotcaster_support", "owner", "manager"].includes(state.auth?.user?.role)) return;
  try {
    state.team = await api("/api/team");
    renderTeam();
  } catch (error) {
    els.teamStatus.textContent = error.message || "Could not load the team dashboard.";
  }
}

async function addTeamUser(event) {
  event.preventDefault();
  try {
    state.team = await api("/api/team/users", {
      method: "POST",
      body: JSON.stringify({
        name: els.teamUserName.value,
        email: els.teamUserEmail.value,
        role: els.teamUserRole.value,
        password: els.teamUserPassword.value
      })
    });
    els.teamUserForm.reset();
    if (state.auth.user.role === "manager") {
      els.teamUserRole.value = "salesperson";
      els.teamUserRole.disabled = true;
    }
    renderTeam();
    render();
    els.teamStatus.textContent = state.auth?.hosted
      ? "Invitation sent. The team member will create their password from the email link."
      : "Team member added. Give them their email and temporary password privately.";
  } catch (error) {
    els.teamStatus.textContent = error.message || "Could not add the team member.";
  }
}

function renderTeam() {
  const totals = state.team.totals || {};
  els.teamAssignedCount.textContent = String(totals.assigned || 0);
  els.teamPreparedCount.textContent = String(totals.prepared || 0);
  els.teamPostedCount.textContent = String(totals.posted || 0);
  els.teamUnassignedCount.textContent = String(totals.unassigned || 0);

  const users = state.team.users || [];
  els.teamMemberList.replaceChildren(...users.map((user) => {
    const row = document.createElement("article");
    row.className = "team-member-row";
    const identity = document.createElement("div");
    const name = document.createElement("strong");
    const meta = document.createElement("small");
    const metrics = document.createElement("div");
    const status = document.createElement("span");
    const reset = document.createElement("button");
    const toggle = document.createElement("button");
    name.textContent = user.name;
    meta.textContent = `${user.email} | ${user.role} login`;
    metrics.className = "member-metrics";
    metrics.textContent = `${user.assigned} assigned | ${user.prepared} prepared | ${user.posted} posted${user.overdue ? ` | ${user.overdue} overdue` : ""}`;
    status.className = `dealer-status ${user.status}`;
    status.textContent = user.status;
    reset.type = "button";
    reset.className = "secondary compact-button";
    reset.textContent = "Reset Password";
    reset.addEventListener("click", () => resetTeamPassword(user));
    toggle.type = "button";
    toggle.className = user.status === "active" ? "suspend-button" : "activate-button";
    toggle.textContent = user.status === "active" ? "Deactivate" : "Reactivate";
    toggle.addEventListener("click", () => setTeamUserStatus(user, user.status === "active" ? "inactive" : "active"));
    identity.append(name, meta, metrics);
    row.append(identity, status, reset, toggle);
    return row;
  }));

  const activity = state.team.activity || [];
  els.teamActivityList.replaceChildren(...activity.map((entry) => {
    const row = document.createElement("article");
    const title = document.createElement("strong");
    const details = document.createElement("p");
    const time = document.createElement("small");
    title.textContent = `${entry.userName || "System"}: ${formatActivityType(entry.type)}`;
    details.textContent = [entry.vehicleTitle, entry.details].filter(Boolean).join(" | ");
    time.textContent = formatDateTime(entry.createdAt);
    row.append(title, details, time);
    return row;
  }));
  if (!users.length) els.teamMemberList.textContent = "No managers or salespeople have been added yet.";
  if (!activity.length) els.teamActivityList.textContent = "No team activity has been recorded yet.";
}

async function setTeamUserStatus(user, status) {
  try {
    state.team = await api("/api/team/user-status", {
      method: "POST",
      body: JSON.stringify({ id: user.id, status })
    });
    renderTeam();
    render();
    els.teamStatus.textContent = `${user.name} is now ${status}.`;
  } catch (error) {
    els.teamStatus.textContent = error.message || "Could not update team access.";
  }
}

async function resetTeamPassword(user) {
  if (state.auth?.hosted) {
    try {
      state.team = await api("/api/team/reset-password", {
        method: "POST",
        body: JSON.stringify({ id: user.id })
      });
      renderTeam();
      els.teamStatus.textContent = `A secure password-reset email was sent to ${user.email}.`;
    } catch (error) {
      els.teamStatus.textContent = error.message || "Could not send the password-reset email.";
    }
    return;
  }
  const password = window.prompt(`Enter a new temporary password for ${user.name}. Use at least 8 characters.`);
  if (!password) return;
  if (password.length < 8) {
    els.teamStatus.textContent = "Temporary password must be at least 8 characters.";
    return;
  }
  try {
    state.team = await api("/api/team/reset-password", {
      method: "POST",
      body: JSON.stringify({ id: user.id, password })
    });
    renderTeam();
    els.teamStatus.textContent = `${user.name} can now sign in with the new temporary password.`;
  } catch (error) {
    els.teamStatus.textContent = error.message || "Could not reset the password.";
  }
}

function formatActivityType(type) {
  return ({
    assigned: "assigned vehicle",
    unassigned: "removed assignment",
    prepared: "prepared listing",
    posted: "marked vehicle posted",
    unposted: "returned vehicle to queue",
    user_created: "added team member",
    user_status: "updated team access",
    password_reset: "reset login password"
  })[type] || String(type || "activity").replace(/_/g, " ");
}

async function logout() {
  await api("/api/auth/logout", { method: "POST", body: "{}" });
  state.auth = { setupRequired: false, authenticated: false };
  state.settings = null;
  state.team = { users: [], activity: [], totals: {} };
  state.store = { vehicles: [], removed: [] };
  showAuth();
}

async function loadSettings() {
  state.settings = await api("/api/settings");
  els.inventoryUrl.value = state.settings.inventoryUrl;
  els.openInventoryLink.href = state.settings.inventoryUrl;
  els.docFee.value = state.settings.docFee || "";
  els.sourcePriceIncludesDocFee.checked = Boolean(state.settings.sourcePriceIncludesDocFee);
  els.dealershipName.value = state.settings.dealershipName;
  els.city.value = state.settings.city;
  els.listingFooter.value = state.settings.listingFooter;
  updateSourceNote();
}

async function saveSettingsOnly() {
  try {
    state.settings = await api("/api/settings", {
      method: "POST",
      body: JSON.stringify(currentSettings())
    });
    els.inventoryUrl.value = state.settings.inventoryUrl;
    els.openInventoryLink.href = state.settings.inventoryUrl;
    updateSourceNote();
    setStatus("Inventory source saved. Import when you are ready.");
  } catch (error) {
    setStatus(error.message || "Could not save the inventory source.");
  }
}

async function useWalkerSource() {
  els.inventoryUrl.value = "https://www.autotrader.com/car-dealers/nashville-tn/100009092/walker-chevrolet?listingType=USED";
  els.dealershipName.value = "Walker Chevrolet";
  els.city.value = "Franklin, TN";
  els.openInventoryLink.href = els.inventoryUrl.value;
  updateSourceNote();
  await saveSettingsOnly();
}

function updateSourceNote() {
  const value = (els.inventoryUrl.value || "").toLowerCase();
  if (!els.sourceNote) return;
  if (value.includes("autotrader.com")) {
    els.sourceNote.textContent = "AutoTrader dealer pages are the most complete source right now. LotCaster will request up to 100 used vehicles.";
  } else if (value.includes("cars.com") || value.includes("cargurus.com")) {
    els.sourceNote.textContent = "Cars.com and CarGurus need dedicated import support. Save the source for the dealer record, then use CSV/manual import until that adapter is added.";
  } else {
    els.sourceNote.textContent = "Generic website imports may work when the page exposes vehicle data. CSV/manual import remains the reliable fallback.";
  }
}

async function loadInventory() {
  state.store = await api("/api/inventory");
}

async function refreshInventory() {
  setBusy(true, "Refreshing inventory...");
  try {
    state.store = await api("/api/scrape", {
      method: "POST",
      body: JSON.stringify(currentSettings())
    });
    if (state.store.refreshFailed && isFacebookHelperInstalled()) {
      setStatus("Direct refresh was blocked. Retrying through the LotCaster browser helper...");
      const source = await requestInventorySourceFromHelper(els.inventoryUrl.value);
      state.store = await api("/api/import-html", {
        method: "POST",
        body: JSON.stringify({ ...currentSettings(), sourceUrl: source.url, html: source.html, pages: source.pages })
      });
    }
    render();
    setStatus(formatImportResult(state.store));
  } catch (error) {
    if (/sendMessage|extension context invalidated|receiving end does not exist/i.test(error?.message || "")) {
      sessionStorage.setItem("lotcasterResumeRefresh", "1");
      setStatus("The browser helper was updated. Reconnecting and resuming refresh...");
      window.setTimeout(() => window.location.reload(), 100);
      return;
    }
    setStatus(error.message || "Refresh failed.");
  } finally {
    setBusy(false);
  }
}

async function autoImportInventory() {
  setBusy(true, "Importing from the Inventory Source...");
  try {
    state.store = await api("/api/auto-import", {
      method: "POST",
      body: JSON.stringify(currentSettings())
    });
    render();
    setStatus(formatImportResult(state.store));
  } catch (error) {
    setStatus(error.message || "Auto import failed.");
  } finally {
    setBusy(false);
  }
}

async function saveManualVehicle() {
  const vehicle = {
    title: els.manualTitle.value,
    price: els.manualPrice.value,
    mileage: els.manualMileage.value,
    vin: els.manualVin.value,
    stock: els.manualStock.value,
    url: els.manualUrl.value,
    image: els.manualImage.value,
    bodyType: els.manualBodyType.value
  };
  if (!vehicle.title.trim()) {
    setStatus("Add a vehicle title first.");
    return;
  }
  setBusy(true, "Saving vehicle...");
  try {
    state.store = await api("/api/manual", {
      method: "POST",
      body: JSON.stringify({ ...currentSettings(), vehicle })
    });
    clearManualForm();
    render();
    setStatus(`Saved ${vehicle.title.trim()}.`);
  } catch (error) {
    setStatus(error.message || "Vehicle save failed.");
  } finally {
    setBusy(false);
  }
}

function clearManualForm() {
  [els.manualTitle, els.manualPrice, els.manualMileage, els.manualVin, els.manualStock, els.manualUrl, els.manualImage].forEach((input) => {
    input.value = "";
  });
  els.manualBodyType.value = "unknown";
}

async function importInventory() {
  const csvText = (await getImportCsvText()).trim();
  if (!csvText) {
    setStatus("Choose a CSV file or paste CSV text first.");
    return;
  }
  setBusy(true, "Importing CSV...");
  try {
    state.store = await api("/api/import", {
      method: "POST",
      body: JSON.stringify({ ...currentSettings(), csvText })
    });
    els.importText.value = "";
    els.importFile.value = "";
    render();
    setStatus(`Imported ${state.store.vehicles.length} active vehicles at ${formatDateTime(state.store.scrapedAt)}.`);
  } catch (error) {
    setStatus(error.message || "Import failed.");
  } finally {
    setBusy(false);
  }
}

async function importPastedPage() {
  const pageText = (await getImportCsvText()).trim();
  if (!pageText) {
    setStatus("Paste copied inventory page text first.");
    return;
  }
  setBusy(true, "Importing pasted inventory page...");
  try {
    state.store = await api("/api/import-page", {
      method: "POST",
      body: JSON.stringify({ ...currentSettings(), pageText })
    });
    els.importText.value = "";
    els.importFile.value = "";
    render();
    setStatus(formatImportResult(state.store));
  } catch (error) {
    setStatus(error.message || "Pasted page import failed.");
  } finally {
    setBusy(false);
  }
}

async function getImportCsvText() {
  const file = els.importFile.files?.[0];
  if (file) return await file.text();
  return els.importText.value;
}

function currentSettings() {
  return {
    inventoryUrl: els.inventoryUrl.value,
    docFee: els.docFee.value,
    sourcePriceIncludesDocFee: els.sourcePriceIncludesDocFee.checked,
    dealershipName: els.dealershipName.value,
    city: els.city.value,
    listingFooter: els.listingFooter.value
  };
}

function render() {
  const active = state.store.vehicles || [];
  const removed = state.store.removed || [];
  const all = [...active, ...removed];
  const query = els.searchInput.value.trim().toLowerCase();
  const filter = els.statusFilter.value;
  const source = filter === "removed" ? removed : filter === "all" ? all : active;
  const vehicles = source.filter((vehicle) => {
    const matchesStatus = filter === "new" ? vehicle.status === "new" : true;
    const matchesFacebook =
      filter === "posted" ? Boolean(vehicle.facebookPostedAt) :
      filter === "unposted" ? !vehicle.facebookPostedAt :
      true;
    const text = [vehicle.title, vehicle.price, vehicle.mileage, vehicle.vin, vehicle.stock].join(" ").toLowerCase();
    return matchesStatus && matchesFacebook && matchesQueueFocus(vehicle) && (!query || text.includes(query));
  });

  els.vehicleCount.textContent = String(active.length);
  els.newCount.textContent = String(active.filter((vehicle) => vehicle.status === "new").length);
  els.removedCount.textContent = String(removed.length);
  els.postedCount.textContent = String(active.filter((vehicle) => vehicle.facebookPostedAt).length);
  els.vehicleGrid.replaceChildren(...vehicles.map(renderVehicle));
  updateAutoCsvLink();

  if (!vehicles.length) {
    els.statusMessage.textContent = state.store.scrapedAt
      ? "No vehicles match the current filter."
      : "No saved inventory yet. Refresh inventory to start tracking.";
  } else {
    els.statusMessage.textContent = state.store.scrapedAt ? `Last refreshed ${formatDateTime(state.store.scrapedAt)}` : "";
  }
}

function renderPostingCenter() {
  const active = state.store.vehicles || [];
  const now = Date.now();
  const isOverdue = (vehicle) => vehicle.assignmentDueAt && !vehicle.facebookPostedAt && new Date(vehicle.assignmentDueAt).getTime() < now;
  const unassigned = active.filter((vehicle) => !vehicle.assignedToId && !vehicle.facebookPostedAt);
  const needsPrep = active.filter((vehicle) => vehicle.assignedToId && !vehicle.preparedAt && !vehicle.facebookPostedAt);
  const ready = active.filter((vehicle) => vehicle.preparedAt && !vehicle.facebookPostedAt);
  const posted = active.filter((vehicle) => vehicle.facebookPostedAt);
  const overdue = active.filter(isOverdue);

  els.postingSourceBadge.textContent = state.store.sourceUrl ? sourceLabel(state.store.sourceUrl) : "Inventory";
  els.queueUnassignedCount.textContent = String(unassigned.length);
  els.queuePrepCount.textContent = String(needsPrep.length);
  els.queueReadyCount.textContent = String(ready.length);
  els.queuePostedCount.textContent = String(posted.length);
  els.queueOverdueCount.textContent = String(overdue.length);

  const priority = [
    ...overdue.map((vehicle) => ({ vehicle, reason: "Overdue" })),
    ...unassigned.slice(0, 8).map((vehicle) => ({ vehicle, reason: "Needs owner" })),
    ...needsPrep.slice(0, 8).map((vehicle) => ({ vehicle, reason: "Needs details" })),
    ...ready.slice(0, 8).map((vehicle) => ({ vehicle, reason: "Ready to post" }))
  ].filter((item, index, items) => items.findIndex((other) => other.vehicle.id === item.vehicle.id) === index).slice(0, 16);

  els.postingQueueList.replaceChildren(...priority.map(renderPostingQueueRow));
  if (!priority.length) els.postingQueueList.textContent = "No active posting work is waiting.";

  const people = postingPeopleSnapshot(active);
  els.postingPeopleList.replaceChildren(...people.map(renderPostingPersonRow));
  if (!people.length) els.postingPeopleList.textContent = "Add salespeople and assign vehicles to see posting progress.";
}

function renderPostingQueueRow(item) {
  const { vehicle, reason } = item;
  const row = document.createElement("article");
  const main = document.createElement("div");
  const title = document.createElement("strong");
  const meta = document.createElement("small");
  const action = document.createElement("button");
  title.textContent = vehicle.title;
  meta.textContent = [
    reason,
    vehicle.assignedToName ? `Owner: ${vehicle.assignedToName}` : "Unassigned",
    vehicle.assignmentDueAt ? `Due: ${formatDate(vehicle.assignmentDueAt)}` : "",
    vehicle.stock ? `Stock ${vehicle.stock}` : ""
  ].filter(Boolean).join(" | ");
  action.type = "button";
  action.className = "secondary compact-button";
  action.textContent = "Open";
  action.addEventListener("click", () => openInventorySearch(vehicle));
  main.append(title, meta);
  row.append(main, action);
  return row;
}

function postingPeopleSnapshot(active) {
  const users = (state.team.users || []).filter((user) => user.role === "salesperson");
  return users.map((user) => {
    const assigned = active.filter((vehicle) => vehicle.assignedToId === user.id);
    return {
      name: user.name,
      status: user.status,
      assigned: assigned.length,
      ready: assigned.filter((vehicle) => vehicle.preparedAt && !vehicle.facebookPostedAt).length,
      posted: assigned.filter((vehicle) => vehicle.facebookPostedAt).length,
      overdue: assigned.filter((vehicle) => vehicle.assignmentDueAt && !vehicle.facebookPostedAt && new Date(vehicle.assignmentDueAt).getTime() < Date.now()).length
    };
  }).sort((a, b) => (b.overdue - a.overdue) || (b.ready - a.ready) || (b.assigned - a.assigned));
}

function renderPostingPersonRow(person) {
  const row = document.createElement("article");
  const name = document.createElement("strong");
  const meta = document.createElement("small");
  name.textContent = `${person.name}${person.status === "inactive" ? " (inactive)" : ""}`;
  meta.textContent = `${person.assigned} assigned | ${person.ready} ready | ${person.posted} posted${person.overdue ? ` | ${person.overdue} overdue` : ""}`;
  row.append(name, meta);
  return row;
}

function openInventoryFilter(filter, label) {
  showWorkspace("inventory");
  els.statusFilter.value = filter;
  els.searchInput.value = "";
  state.queueFocus = label;
  render();
  setStatus(`Showing ${label}.`);
}

function openInventorySearch(vehicle) {
  showWorkspace("inventory");
  els.statusFilter.value = "all";
  state.queueFocus = null;
  els.searchInput.value = vehicle.vin || vehicle.stock || vehicle.title;
  render();
  setStatus(`Opened ${vehicle.title}.`);
}

function matchesQueueFocus(vehicle) {
  if (!state.queueFocus) return true;
  const overdue = vehicle.assignmentDueAt && !vehicle.facebookPostedAt && new Date(vehicle.assignmentDueAt).getTime() < Date.now();
  if (state.queueFocus === "unassigned") return !vehicle.assignedToId && !vehicle.facebookPostedAt;
  if (state.queueFocus === "needs details") return vehicle.assignedToId && !vehicle.preparedAt && !vehicle.facebookPostedAt;
  if (state.queueFocus === "ready to post") return vehicle.preparedAt && !vehicle.facebookPostedAt;
  if (state.queueFocus === "posted") return Boolean(vehicle.facebookPostedAt);
  if (state.queueFocus === "overdue") return overdue;
  return true;
}

function sourceLabel(value) {
  try {
    return new URL(value).hostname.replace(/^www\./, "");
  } catch {
    return "Inventory";
  }
}

function updateAutoCsvLink() {
  const hasAutoCsv = Boolean(state.store.autoCsvAvailable) || (state.store.vehicles || []).length > 0;
  els.autoCsvLink.classList.toggle("disabled-link", !hasAutoCsv);
  els.autoCsvLink.setAttribute("aria-disabled", String(!hasAutoCsv));
  els.autoCsvLink.title = hasAutoCsv ? "Download the latest inventory CSV" : "No vehicle rows have been imported yet";
}

function renderVehicle(vehicle) {
  const node = els.template.content.firstElementChild.cloneNode(true);
  const photo = node.querySelector(".photo");
  const title = node.querySelector("h2");
  const badge = node.querySelector(".badge");
  const facts = node.querySelector(".facts");
  const details = node.querySelector(".details");
  const copy = node.querySelector(".copy");
  const facebook = node.querySelector(".facebook");
  const postedToggle = node.querySelector(".posted-toggle");
  const photoLink = node.querySelector(".photo-link");
  const listing = node.querySelector(".listing");
  const assignmentSummary = node.querySelector(".assignment-summary");
  const assignmentControls = node.querySelector(".assignment-controls");
  const assigneeSelect = node.querySelector(".assignee-select");
  const assignmentDue = node.querySelector(".assignment-due");
  const assignButton = node.querySelector(".assign-button");

  title.textContent = vehicle.title;
  badge.textContent = vehicle.status || "seen";
  badge.className = `badge ${vehicle.status || "seen"}`;
  listing.value = compliantDescription(vehicle, vehicle.marketplaceText || buildFallbackListing(vehicle));

  if (vehicle.image) {
    const img = document.createElement("img");
    img.alt = vehicle.title;
    img.loading = "lazy";
    img.src = vehicle.image;
    photo.replaceChildren(img);
    photoLink.href = vehicle.image;
  } else {
    photo.textContent = "No photo found";
    photoLink.removeAttribute("href");
    photoLink.setAttribute("aria-disabled", "true");
  }

  facts.replaceChildren(
    fact(
      priceVerifiedToday(vehicle) ? "Verified posting price" : "Price not verified",
      priceVerifiedToday(vehicle) ? postingPriceText(vehicle) || "Check listing" : "Refresh required"
    ),
    fact("Mileage", vehicle.mileage || "Ask dealer"),
    fact("Stock", vehicle.stock || "N/A"),
    fact("VIN", vehicle.vin || "N/A"),
    fact("Category", displayBodyType(vehicle.bodyType)),
    fact("Body style", vehicle.bodyStyle || "Review"),
    fact("Exterior", vehicle.exteriorColor || "Review"),
    fact("Photos", String(vehiclePhotos(vehicle).length)),
    fact("Workflow", displayWorkflowStatus(vehicle)),
    fact("Assigned", vehicle.assignedToName || "Unassigned")
  );

  assignmentSummary.textContent = buildAssignmentSummary(vehicle);
  const canManageAssignments = ["master", "lotcaster_general_manager", "lotcaster_manager", "lotcaster_support", "owner", "manager"].includes(state.auth?.user?.role);
  assignmentControls.hidden = !canManageAssignments;
  if (canManageAssignments) {
    const activeSalespeople = (state.team.users || []).filter((user) => user.role === "salesperson" && user.status === "active");
    assigneeSelect.replaceChildren(
      new Option("Unassigned", ""),
      ...activeSalespeople.map((user) => new Option(user.name, user.id))
    );
    assigneeSelect.value = vehicle.assignedToId || "";
    assignmentDue.value = vehicle.assignmentDueAt ? String(vehicle.assignmentDueAt).slice(0, 10) : "";
    assignButton.addEventListener("click", async () => {
      assignButton.disabled = true;
      try {
        const result = await api("/api/team/assign", {
          method: "POST",
          body: JSON.stringify({
            vehicleId: vehicle.id,
            userId: assigneeSelect.value,
            dueAt: assignmentDue.value || null
          })
        });
        state.store = result.store;
        state.team = result.team;
        render();
        if (!els.teamView.hidden) renderTeam();
        setStatus(assigneeSelect.value ? `${vehicle.title} assigned.` : `${vehicle.title} returned to the unassigned queue.`);
      } catch (error) {
        setStatus(error.message || "Could not save the assignment.");
        assignButton.disabled = false;
      }
    });
  }

  if (vehicle.url) {
    details.href = vehicle.url;
  } else {
    details.removeAttribute("href");
    details.setAttribute("aria-disabled", "true");
  }

  copy.addEventListener("click", async () => {
    await copyText(listing.value);
    showTemporaryButtonText(copy, "Copied", "Copy Description");
  });

  facebook.addEventListener("click", () => openPostingSheet(vehicle, listing.value, facebook));

  postedToggle.textContent = vehicle.facebookPostedAt ? "Mark Unposted" : "Mark Posted";
  postedToggle.classList.toggle("is-posted", Boolean(vehicle.facebookPostedAt));
  postedToggle.addEventListener("click", async () => {
    postedToggle.disabled = true;
    try {
      state.store = await api("/api/facebook-status", {
        method: "POST",
        body: JSON.stringify({ id: vehicle.id, posted: !vehicle.facebookPostedAt })
      });
      if (["master", "lotcaster_general_manager", "lotcaster_manager", "lotcaster_support", "owner", "manager"].includes(state.auth?.user?.role)) await loadTeam();
      render();
      setStatus(vehicle.facebookPostedAt ? `${vehicle.title} returned to the posting queue.` : `${vehicle.title} marked as posted.`);
    } catch (error) {
      setStatus(error.message || "Could not update Facebook status.");
      postedToggle.disabled = false;
    }
  });

  return node;
}

function displayWorkflowStatus(vehicle) {
  if (vehicle.facebookPostedAt) return "Posted";
  if (vehicle.preparedAt) return "Prepared";
  if (vehicle.assignedToId) return "Assigned";
  return "Ready";
}

function buildAssignmentSummary(vehicle) {
  const parts = [];
  if (vehicle.assignedToName) parts.push(`Assigned to ${vehicle.assignedToName}`);
  else parts.push("Not assigned");
  if (vehicle.assignmentDueAt) parts.push(`due ${formatDate(vehicle.assignmentDueAt)}`);
  if (vehicle.preparedByName) parts.push(`prepared by ${vehicle.preparedByName}`);
  if (vehicle.postedByName) parts.push(`posted by ${vehicle.postedByName}`);
  return parts.join(" | ");
}

async function openPostingSheet(vehicle, description, triggerButton) {
  let preparedVehicle = vehicle;
  triggerButton.textContent = "Loading Photos...";
  triggerButton.disabled = true;
  try {
    const result = await api("/api/vehicle-photos", {
      method: "POST",
      body: JSON.stringify({ id: vehicle.id })
    });
    preparedVehicle = result.vehicle || vehicle;
    if (vehiclePhotos(preparedVehicle).length <= 1 && isFacebookHelperInstalled() && /^https:\/\/(?:www\.)?autotrader\.com\//i.test(preparedVehicle.url || "")) {
      triggerButton.textContent = "Loading Photo Gallery...";
      const source = await requestInventorySourceFromHelper(preparedVehicle.url);
      const galleryResult = await api("/api/import-vehicle-html", {
        method: "POST",
        body: JSON.stringify({ id: vehicle.id, sourceUrl: source.url, html: source.html })
      });
      preparedVehicle = galleryResult.vehicle || preparedVehicle;
    }
    const index = (state.store.vehicles || []).findIndex((item) => item.id === vehicle.id);
    if (index >= 0) state.store.vehicles[index] = preparedVehicle;
  } catch (error) {
    setStatus(`${vehicle.title}: ${error.message} The primary photo will still be available.`);
  } finally {
    triggerButton.textContent = "Build Listing Packet";
    triggerButton.disabled = false;
  }

  preparedVehicle = {
    ...preparedVehicle,
    exteriorColor: simpleVehicleColor(preparedVehicle.exteriorColor),
    interiorColor: simpleVehicleColor(preparedVehicle.interiorColor)
  };
  const photos = vehiclePhotos(preparedVehicle).slice(0, 8);
  const preparedDescription = compliantDescription(preparedVehicle, preparedVehicle.customDescription || preparedVehicle.marketplaceText || description || buildFallbackListing(preparedVehicle));
  const fields = [
    ["Title", preparedVehicle.title],
    ["Year", preparedVehicle.year],
    ["Make", preparedVehicle.make],
    ["Model", preparedVehicle.model],
    ["Trim", preparedVehicle.trim],
    ["Posting price", digitsOnly(postingPriceText(preparedVehicle) || preparedVehicle.postingPrice || preparedVehicle.price)],
    ["Website/source price", preparedVehicle.price],
    ["Price verified", preparedVehicle.priceVerifiedAt ? formatDateTime(preparedVehicle.priceVerifiedAt) : "Not verified by refresh"],
    ["Dealer doc fee", docFeeText()],
    ["Doc fee handling", preparedVehicle.sourcePriceIncludesDocFee === true || state.settings?.sourcePriceIncludesDocFee
      ? "Source confirms dealer fees are included; no fee added"
      : `Added configured dealer doc fee of ${docFeeText() || "$0"}`],
    ["Mileage", digitsOnly(preparedVehicle.mileage)],
    ["VIN", preparedVehicle.vin],
    ["Stock number", preparedVehicle.stock],
    ["Category", displayBodyType(preparedVehicle.bodyType)],
    ["Body style", preparedVehicle.bodyStyle],
    ["Exterior color", preparedVehicle.exteriorColor],
    ["Interior color", preparedVehicle.interiorColor],
    ["Fuel type", preparedVehicle.fuelType],
    ["Condition", preparedVehicle.condition || "Excellent"],
    ["Photo count", String(vehiclePhotos(preparedVehicle).length)],
    ["Source URL", preparedVehicle.url],
    ["Last refreshed", preparedVehicle.lastSeenAt ? formatDateTime(preparedVehicle.lastSeenAt) : ""],
    ["Assigned to", preparedVehicle.assignedToName || "Unassigned"],
    ["Prepared by", preparedVehicle.preparedByName || "Not prepared"],
    ["Facebook category", preparedVehicle.facebookListingType || "Car/Truck"],
    ["Posted status", preparedVehicle.facebookPostedAt ? `Posted by ${preparedVehicle.postedByName || "team member"} ${formatDateTime(preparedVehicle.facebookPostedAt)}` : "Not marked posted"]
  ];

  els.postingTitle.textContent = preparedVehicle.title;
  els.postingDescription.value = preparedDescription;
  els.facebookDialog.dataset.vehicleId = preparedVehicle.id;
  els.postingBodyType.value = "Car/Truck";
  els.postingBodyStyle.value = preparedVehicle.bodyStyle || "";
  els.postingExteriorColor.value = preparedVehicle.exteriorColor || "";
  els.postingInteriorColor.value = preparedVehicle.interiorColor || "";
  els.postingFuelType.value = preparedVehicle.fuelType || "";
  els.postingFields.replaceChildren(...fields.map(([label, value]) => postingField(label, value || "")));
  renderPacketPhotos(photos);
  renderRequiredChecklist(preparedVehicle, preparedDescription);
  updateHelperStatus();

  if (preparedVehicle.image) {
    els.postingPhotoLink.href = preparedVehicle.image;
    els.postingPhotoLink.removeAttribute("aria-disabled");
  } else {
    els.postingPhotoLink.removeAttribute("href");
    els.postingPhotoLink.setAttribute("aria-disabled", "true");
  }

  els.facebookDialog.showModal();
}

async function openFacebookWithVehicle() {
  if (els.openFacebookButton.disabled) return;
  let vehicle = selectedPacketVehicle();
  if (!vehicle) {
    setStatus("The selected vehicle could not be found.");
    return;
  }
  if (!priceVerifiedToday(vehicle)) {
    setStatus(`${vehicle.title}: price has not been verified by a successful inventory refresh today. Refresh inventory before publishing.`);
    return;
  }
  const identityIssues = getVehicleIdentityIssues(vehicle);
  if (identityIssues.length) {
    setStatus(`${vehicle.title}: Facebook workflow blocked because ${identityIssues.join("; ")}. Refresh or correct the inventory record before continuing.`);
    return;
  }

  const facebookTab = window.open("about:blank", "_blank");
  if (!facebookTab) {
    setStatus("Your browser blocked the Facebook window. Allow popups for LotCaster, then press Open Facebook Workflow again.");
    return;
  }
  els.openFacebookButton.disabled = true;
  els.openFacebookButton.textContent = "Preparing Facebook...";

  try {
    vehicle = await persistListingDetails(false);
  } catch (error) {
    facebookTab.close();
    setStatus(error.message || "Save the listing details before opening Facebook.");
    els.openFacebookButton.disabled = false;
    els.openFacebookButton.textContent = "Open Facebook Workflow";
    return;
  }

  const missing = getMissingRequiredFields(vehicle, els.postingDescription.value);
  if (missing.length) {
    const proceed = window.confirm(`This Listing Packet still needs: ${missing.join(", ")}. Open Facebook anyway for manual review?`);
    if (!proceed) {
      facebookTab.close();
      els.openFacebookButton.disabled = false;
      els.openFacebookButton.textContent = "Open Facebook Workflow";
      return;
    }
  }

  const payload = {
    title: vehicle.title,
    year: vehicle.year,
    make: vehicle.make,
    model: vehicle.model,
    trim: vehicle.trim,
    sourcePrice: vehicle.sourcePrice || vehicle.price,
    postingPrice: postingPriceText(vehicle) || vehicle.postingPrice,
    docFee: vehicle.docFee || docFeeText(),
    sourcePriceIncludesDocFee: vehicle.sourcePriceIncludesDocFee === true || Boolean(state.settings?.sourcePriceIncludesDocFee),
    priceVerifiedAt: vehicle.priceVerifiedAt,
    price: digitsOnly(postingPriceText(vehicle) || vehicle.postingPrice || vehicle.price),
    mileage: digitsOnly(vehicle.mileage),
    vin: vehicle.vin,
    stock: vehicle.stock,
    facebookListingType: vehicle.facebookListingType || els.postingBodyType.value || "Car/Truck",
    bodyType: vehicle.bodyType,
    bodyStyle: vehicle.bodyStyle,
    exteriorColor: simpleVehicleColor(vehicle.exteriorColor),
    interiorColor: simpleVehicleColor(vehicle.interiorColor),
    fuelType: vehicle.fuelType,
    condition: vehicle.condition || "Excellent",
    description: els.postingDescription.value,
    image: vehicle.image,
    images: vehiclePhotos(vehicle).slice(0, 8),
    url: vehicle.url
  };
  const encoded = encodePayload(payload);
  const facebookUrl = `https://www.facebook.com/marketplace/create/vehicle#lotcaster=${encoded}`;
  if (facebookTab.closed) {
    setStatus("The prepared Facebook window was closed before LotCaster finished saving. Press Open Facebook Workflow again.");
    els.openFacebookButton.disabled = false;
    els.openFacebookButton.textContent = "Open Facebook Workflow";
    return;
  }
  try {
    facebookTab.location.replace(facebookUrl);
  } catch {
    facebookTab.close();
    setStatus("LotCaster could not navigate the prepared Facebook window. Allow popups and try again.");
    els.openFacebookButton.disabled = false;
    els.openFacebookButton.textContent = "Open Facebook Workflow";
    return;
  }
  els.openFacebookButton.disabled = false;
  els.openFacebookButton.textContent = "Open Facebook Workflow";
  const helperNote = isFacebookHelperInstalled()
    ? "The helper is connected."
    : "If Facebook does not fill after you choose Vehicle, reload the LotCaster helper extension once.";
  setStatus(`${vehicle.title} opened in the Facebook workflow. ${helperNote} Review every field before publishing.`);
}

function encodePayload(value) {
  const bytes = new TextEncoder().encode(JSON.stringify(value));
  let binary = "";
  bytes.forEach((byte) => {
    binary += String.fromCharCode(byte);
  });
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function isFacebookHelperInstalled() {
  return /^1\.(?:[4-9]|\d{2,})\./.test(document.documentElement.dataset.walkerFacebookHelper || "");
}

function requestInventorySourceFromHelper(url) {
  return new Promise((resolve, reject) => {
    const requestId = crypto.randomUUID();
    const timeout = window.setTimeout(() => {
      window.removeEventListener("message", onMessage);
      reject(new Error("The browser helper did not return the inventory source. Reload the extension and try again."));
    }, 60000);
    function onMessage(event) {
      if (event.source !== window || event.data?.type !== "lotcaster-inventory-source-result" || event.data.requestId !== requestId) return;
      window.clearTimeout(timeout);
      window.removeEventListener("message", onMessage);
      if (event.data.error) reject(new Error(event.data.error));
      else resolve(event.data);
    }
    window.addEventListener("message", onMessage);
    window.postMessage({ type: "lotcaster-fetch-inventory-source", requestId, url }, window.location.origin);
  });
}

function updateHelperStatus() {
  els.facebookHelperStatus.textContent = isFacebookHelperInstalled()
    ? "Experimental helper is connected. Facebook's listing type should be Car/Truck; LotCaster handles body style, colors, and details after that form appears."
    : "Experimental helper is not connected. The Listing Packet copy controls remain fully available.";
}

function checkHelperConnection() {
  els.facebookHelperStatus.textContent = "Checking Facebook Helper...";
  window.dispatchEvent(new Event("walker-facebook-helper-check"));
  window.setTimeout(updateHelperStatus, 350);
}

function postingField(label, value) {
  const row = document.createElement("div");
  row.className = "posting-field";
  const text = document.createElement("div");
  const name = document.createElement("small");
  const output = document.createElement("strong");
  const button = document.createElement("button");
  name.textContent = label;
  output.textContent = value || "Not available";
  button.type = "button";
  button.className = "secondary";
  button.textContent = "Copy";
  button.disabled = !value;
  button.addEventListener("click", async () => {
    await copyText(value);
    showTemporaryButtonText(button, "Copied", "Copy");
  });
  text.append(name, output);
  row.append(text, button);
  return row;
}

function selectedPacketVehicle() {
  return (state.store.vehicles || []).find((item) => item.id === els.facebookDialog.dataset.vehicleId);
}

async function saveVehicleBodyType() {
  els.saveBodyTypeButton.disabled = true;
  try {
    await persistListingDetails(true);
    showTemporaryButtonText(els.saveBodyTypeButton, "Saved", "Save Listing Details");
  } catch (error) {
    setStatus(error.message || "Could not save the listing details.");
  } finally {
    els.saveBodyTypeButton.disabled = false;
  }
}

async function persistListingDetails(renderWorkspace) {
  const vehicle = selectedPacketVehicle();
  if (!vehicle) throw new Error("The selected vehicle could not be found.");
  const result = await api("/api/vehicle-details", {
    method: "POST",
    body: JSON.stringify({
      id: vehicle.id,
      bodyType: vehicle.bodyType,
      facebookListingType: "Car/Truck",
      bodyStyle: els.postingBodyStyle.value,
      exteriorColor: simpleVehicleColor(els.postingExteriorColor.value),
      interiorColor: simpleVehicleColor(els.postingInteriorColor.value),
      fuelType: els.postingFuelType.value,
      customDescription:
        vehicle.customDescription ||
        (els.postingDescription.value.trim() !== String(vehicle.marketplaceText || "").trim()
          ? els.postingDescription.value
          : "")
    })
  });
  const index = (state.store.vehicles || []).findIndex((item) => item.id === vehicle.id);
  if (index >= 0) state.store.vehicles[index] = result.vehicle;
  els.postingDescription.value = result.vehicle.customDescription || result.vehicle.marketplaceText || els.postingDescription.value;
  renderRequiredChecklist(result.vehicle, els.postingDescription.value);
  if (renderWorkspace) render();
  if (["master", "lotcaster_general_manager", "lotcaster_manager", "lotcaster_support", "owner", "manager"].includes(state.auth?.user?.role)) await loadTeam();
  return result.vehicle;
}

function vehiclePhotos(vehicle) {
  return [...new Set([...(Array.isArray(vehicle.images) ? vehicle.images : []), vehicle.image].filter(isDisplayableVehiclePhoto))];
}

function isDisplayableVehiclePhoto(value) {
  try {
    const url = new URL(String(value || ""));
    if (!/^https?:$/.test(url.protocol)) return false;
    if (/(logo|sprite|placeholder|transparent|blank|favicon|map|avatar|badge|block-images|error-message|no[-_ ]image|image[-_ ]not[-_ ]available)/i.test(url.href)) return false;
    if (/\.(jpe?g|png|webp)$/i.test(url.pathname)) return true;
    return /^(?:images?|photos?|media|cdn)[.-]/i.test(url.hostname) && /\/(?:images?|photos?|media|vehicles?)\//i.test(url.pathname);
  } catch {
    return false;
  }
}

function simpleVehicleColor(value) {
  const text = String(value || "").trim().toLowerCase();
  if (!text) return "";
  if (/\b(black|ebony|onyx|charcoal|jet)\b/.test(text)) return "Black";
  if (/\b(white|pearl|ivory|summit|alabaster|frost|snow)\b/.test(text)) return "White";
  if (/\b(silver|steel|aluminum|aluminium|ingot|metallic)\b/.test(text) && !/\bblue|red|green|brown|orange|gold|purple\b/.test(text)) return "Silver";
  if (/\b(gray|grey|graphite|slate|magnetic|granite|carbon|ash)\b/.test(text)) return "Gray";
  if (/\b(red|maroon|burgundy|crimson|ruby|scarlet|cherry)\b/.test(text)) return "Red";
  if (/\b(blue|navy|aqua|azure|sapphire)\b/.test(text)) return "Blue";
  if (/\b(brown|tan|beige|sand|mocha|cocoa|kalahari|taupe)\b/.test(text)) return "Brown";
  if (/\b(gold|champagne)\b/.test(text)) return "Gold";
  if (/\b(green|olive|emerald)\b/.test(text)) return "Green";
  if (/\b(orange|copper|bronze)\b/.test(text)) return "Orange";
  if (/\b(yellow)\b/.test(text)) return "Yellow";
  if (/\b(purple|plum|violet)\b/.test(text)) return "Purple";
  return "Other";
}

function renderPacketPhotos(photos) {
  if (!photos.length) {
    const empty = document.createElement("p");
    empty.className = "packet-photo-empty";
    empty.textContent = "No authorized vehicle photo is currently available.";
    els.postingPhotos.replaceChildren(empty);
    return;
  }
  els.postingPhotos.replaceChildren(...photos.map((url, index) => {
    const link = document.createElement("a");
    const image = document.createElement("img");
    link.href = url;
    link.target = "_blank";
    link.rel = "noreferrer";
    link.title = `Open photo ${index + 1}`;
    image.src = url;
    image.alt = `Vehicle photo ${index + 1}`;
    image.loading = "lazy";
    link.append(image);
    return link;
  }));
}

function getMissingRequiredFields(vehicle, description) {
  const priceText = postingPriceText(vehicle) || vehicle.price;
  const checks = [
    ["year", vehicle.year],
    ["make", vehicle.make],
    ["model", vehicle.model],
    ["price", digitsOnly(priceText)],
    ["mileage", digitsOnly(vehicle.mileage)],
    ["photo", vehiclePhotos(vehicle).length],
    ["Facebook category", vehicle.facebookListingType === "Car/Truck"],
    ["category/body type", vehicle.bodyType && vehicle.bodyType !== "unknown"],
    ["body style", vehicle.bodyStyle],
    ["exterior color", vehicle.exteriorColor],
    ["fuel type", vehicle.fuelType],
    ["description", String(description || "").trim()]
  ];
  return checks.filter(([, value]) => !value).map(([label]) => label);
}

function getVehicleIdentityIssues(vehicle) {
  const issues = [];
  const title = String(vehicle.title || "").toLowerCase();
  const year = String(vehicle.year || "").trim();
  const make = String(vehicle.make || "").trim();
  const model = String(vehicle.model || "").trim();
  if (year && !title.includes(year.toLowerCase())) issues.push("the title does not match its year");
  if (make && !title.includes(make.toLowerCase())) issues.push("the title does not match its make");
  if (model && !title.includes(model.toLowerCase())) issues.push("the title does not match its model");
  const decodedYear = vinModelYear(vehicle.vin);
  if (decodedYear && year && String(decodedYear) !== year) {
    issues.push(`VIN model year ${decodedYear} does not match ${year}`);
  }
  return issues;
}

function vinModelYear(vin) {
  const normalizedVin = String(vin || "").trim().toUpperCase();
  if (!/^[A-HJ-NPR-Z0-9]{17}$/.test(normalizedVin)) return null;
  const code = normalizedVin[9];
  const modernCodes = "ABCDEFGHJKLMNPRSTVWXY";
  const modernIndex = modernCodes.indexOf(code);
  if (modernIndex >= 0) return 2010 + modernIndex;
  const numericYear = Number(code);
  return numericYear >= 1 && numericYear <= 9 ? 2000 + numericYear : null;
}

function renderRequiredChecklist(vehicle, description) {
  const missing = new Set(getMissingRequiredFields(vehicle, description));
  const names = ["year", "make", "model", "price", "mileage", "photo", "category/body type", "body style", "exterior color", "fuel type", "description"];
  const heading = document.createElement("strong");
  heading.textContent = missing.size ? "Review required fields before leaving LotCaster" : "Listing Packet is ready for final review";
  const list = document.createElement("div");
  list.className = "checklist-items";
  list.replaceChildren(...names.map((name) => {
    const item = document.createElement("span");
    const absent = missing.has(name);
    item.className = absent ? "check-missing" : "check-ready";
    item.textContent = `${absent ? "Missing" : "Ready"}: ${name}`;
    return item;
  }));
  els.requiredChecklist.classList.toggle("has-missing", missing.size > 0);
  els.requiredChecklist.replaceChildren(heading, list);
}

function buildFullListingPacket(vehicle, description) {
  const footer = state.settings?.listingFooter || "";
  const priceInfo = postingPriceInfo(vehicle);
  return [
    `TITLE: ${vehicle.title || ""}`,
    `POSTING PRICE: ${priceInfo.postingText || vehicle.price || ""}`,
    `WEBSITE/SOURCE PRICE: ${vehicle.price || ""}`,
    `DEALER DOC FEE: ${docFeeText() || ""}`,
    `MILEAGE: ${vehicle.mileage || ""}`,
    `VIN: ${vehicle.vin || ""}`,
    `STOCK: ${vehicle.stock || ""}`,
    `CATEGORY: ${displayBodyType(vehicle.bodyType)}`,
    `BODY STYLE: ${vehicle.bodyStyle || ""}`,
    `EXTERIOR COLOR: ${vehicle.exteriorColor || ""}`,
    `INTERIOR COLOR: ${vehicle.interiorColor || ""}`,
    `FUEL TYPE: ${vehicle.fuelType || ""}`,
    `CONDITION: ${vehicle.condition || "Excellent"}`,
    `SOURCE: ${vehicle.url || ""}`,
    `PHOTOS: ${vehiclePhotos(vehicle).length}`,
    `LAST REFRESHED: ${vehicle.lastSeenAt ? formatDateTime(vehicle.lastSeenAt) : ""}`,
    `STATUS: ${vehicle.facebookPostedAt ? "Posted" : "Not marked posted"}`,
    "",
    "DESCRIPTION:",
    description || "",
    footer && !String(description || "").includes(footer) ? `\nDEALERSHIP FOOTER:\n${footer}` : ""
  ].filter((line) => line !== null).join("\n").trim();
}

function displayBodyType(value) {
  if (!value || value === "unknown") return "Unknown";
  return value === "suv" ? "SUV" : value.charAt(0).toUpperCase() + value.slice(1);
}

async function copyText(value) {
  try {
    await navigator.clipboard.writeText(value);
  } catch {
    const helper = document.createElement("textarea");
    helper.value = value;
    helper.setAttribute("readonly", "");
    helper.style.position = "fixed";
    helper.style.opacity = "0";
    document.body.append(helper);
    helper.select();
    document.execCommand("copy");
    helper.remove();
  }
}

function showTemporaryButtonText(button, temporary, original) {
  button.textContent = temporary;
  window.setTimeout(() => {
    button.textContent = original;
  }, 1400);
}

function digitsOnly(value) {
  return String(value || "").replace(/[^\d]/g, "");
}

function fact(label, value) {
  const wrapper = document.createElement("div");
  const dt = document.createElement("dt");
  const dd = document.createElement("dd");
  dt.textContent = label;
  dd.textContent = value;
  wrapper.append(dt, dd);
  return wrapper;
}

function buildFallbackListing(vehicle) {
  const priceInfo = postingPriceInfo(vehicle);
  return [
    vehicle.title,
    priceInfo.postingText || vehicle.price,
    priceDisclosureLine(vehicle),
    vehicle.mileage,
    vehicle.url
  ].filter(Boolean).join("\n");
}

function moneyAmount(value) {
  const parsed = Number(String(value || "").replace(/[^0-9.]/g, ""));
  return Number.isFinite(parsed) ? parsed : 0;
}

function formatMoney(value) {
  if (!value) return "";
  return `$${Math.round(value).toLocaleString("en-US")}`;
}

function postingPriceInfo(vehicle) {
  const base = moneyAmount(vehicle.sourcePrice || vehicle.price);
  const docFee = moneyAmount(state.settings?.docFee);
  const includesDocFee = vehicle.sourcePriceIncludesDocFee === true || Boolean(state.settings?.sourcePriceIncludesDocFee);
  const posting = base ? base + (includesDocFee ? 0 : docFee) : 0;
  return {
    base,
    docFee,
    includesDocFee,
    posting,
    postingText: formatMoney(posting),
    docFeeText: formatMoney(docFee),
    baseText: formatMoney(base)
  };
}

function postingPriceText(vehicle) {
  return postingPriceInfo(vehicle).postingText;
}

function priceVerifiedToday(vehicle) {
  if (!vehicle?.priceVerifiedAt) return false;
  const verified = new Date(vehicle.priceVerifiedAt);
  const today = new Date();
  return !Number.isNaN(verified.getTime()) &&
    verified.getFullYear() === today.getFullYear() &&
    verified.getMonth() === today.getMonth() &&
    verified.getDate() === today.getDate();
}

function docFeeText() {
  return formatMoney(moneyAmount(state.settings?.docFee));
}

function priceDisclosureLine(vehicle) {
  const info = postingPriceInfo(vehicle);
  if (!info.docFee) return "";
  if (info.includesDocFee) {
    return `Dealer doc fee: ${info.docFeeText}. Website/source price is marked as already including this doc fee. Taxes, title, registration, and government fees extra.`;
  }
  return `Website/source price: ${info.baseText || vehicle.price}. Dealer doc fee: ${info.docFeeText}. Posting price includes the dealer doc fee. Taxes, title, registration, and government fees extra.`;
}

function compliantDescription(vehicle, description) {
  const disclosure = priceDisclosureLine(vehicle);
  const info = postingPriceInfo(vehicle);
  let text = String(description || "")
    .replace(/^Price:\s*.*$/gim, "")
    .replace(/^Website\/source price:.*$/gim, "")
    .replace(/^Dealer doc fee:.*$/gim, "")
    .trim();
  if (!priceVerifiedToday(vehicle)) {
    return `PRICE NOT VERIFIED - refresh inventory successfully before publishing.\n${text}`.trim();
  }
  if (info.postingText) {
    text = `Price: ${info.postingText}\n${text}`;
  }
  if (!disclosure) return text;
  return `${text.trim()}\n${disclosure}`.trim();
}

async function api(url, options = {}) {
  const response = await fetch(url, {
    headers: { "content-type": "application/json", ...(options.headers || {}) },
    ...options
  });
  const data = await response.json();
  if (response.status === 401 && !url.startsWith("/api/auth/")) {
    state.auth = { setupRequired: false, authenticated: false };
    showAuth();
  }
  if (!response.ok) throw new Error(data.error || `Request failed with HTTP ${response.status}`);
  return data;
}

function formatDate(value) {
  return new Intl.DateTimeFormat(undefined, { dateStyle: "medium" }).format(new Date(value));
}

function setBusy(isBusy, message = "") {
  els.autoImportButton.disabled = isBusy;
  els.scrapeButton.disabled = isBusy;
  els.manualButton.disabled = isBusy;
  els.importButton.disabled = isBusy;
  els.pageImportButton.disabled = isBusy;
  els.autoImportButton.textContent = isBusy && /^Importing/i.test(message) ? "Importing..." : "Import Inventory";
  els.scrapeButton.textContent = isBusy && /^Refreshing/i.test(message) ? "Refreshing..." : "Refresh Inventory";
  if (message) setStatus(message);
}

function setStatus(message) {
  els.statusMessage.textContent = message;
}

function formatImportResult(store) {
  const result = store.importResult;
  const warnings = store.warnings?.length ? ` Warnings: ${store.warnings.join(" ")}` : "";
  if (store.refreshFailed) return `Refresh failed. No prices were updated.${warnings}`;
  if (!result) return `Inventory updated ${formatDateTime(store.scrapedAt)}.${warnings}`;
  return `Source checked: ${result.sourceChecked || store.sourceUrl || "Inventory Source"}. Found ${result.vehiclesFound}; ${result.newVehicles} new, ${result.updatedVehicles} updated, ${result.missingVehicles} missing/removed.${warnings}`;
}

function formatDateTime(value) {
  if (!value) return "never";
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: "medium",
    timeStyle: "short"
  }).format(new Date(value));
}

function registerServiceWorker() {
  if ("serviceWorker" in navigator) {
    let refreshing = false;
    navigator.serviceWorker.addEventListener("controllerchange", () => {
      if (refreshing) return;
      refreshing = true;
      window.location.reload();
    });
    navigator.serviceWorker.register("/sw.js").catch(() => {});
  }
}

(() => {
  const STYLE_ID = "lotcaster-market-compare-style";
  const FILTER_ID = "lotcaster-condition-filter";
  const DIALOG_ID = "lotcaster-market-compare-dialog";
  let inventory = [];
  let settings = null;
  let observer = null;

  function injectStyles() {
    if (document.getElementById(STYLE_ID)) return;
    const style = document.createElement("style");
    style.id = STYLE_ID;
    style.textContent = `
      #${FILTER_ID}{min-width:150px}
      .lotcaster-market-button{white-space:nowrap}
      #${DIALOG_ID}{width:min(1050px,94vw);max-height:92vh;border:0;border-radius:18px;padding:0;box-shadow:0 24px 80px rgba(15,23,42,.28)}
      #${DIALOG_ID}::backdrop{background:rgba(15,23,42,.5)}
      .lmc-shell{padding:1.15rem;display:grid;gap:1rem;background:#fff;color:#172033}
      .lmc-header{display:flex;justify-content:space-between;gap:1rem;align-items:flex-start}
      .lmc-header h2{margin:.15rem 0 0;font-size:1.4rem}
      .lmc-eyebrow{margin:0;text-transform:uppercase;letter-spacing:.08em;font-size:.72rem;font-weight:800;color:#0f766e}
      .lmc-close{border:0;background:#eef2f7;width:38px;height:38px;border-radius:999px;font-size:1.35rem;cursor:pointer}
      .lmc-note{margin:0;color:#5d6878;font-size:.9rem}
      .lmc-summary{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:.7rem}
      .lmc-summary>div{border:1px solid #dfe5ec;border-radius:13px;padding:.8rem;background:#f9fbfc}
      .lmc-summary small{display:block;color:#6b7280;margin-bottom:.3rem}
      .lmc-summary strong{font-size:1.05rem}
      .lmc-meta{margin:0;color:#5d6878}
      .lmc-source{display:flex;gap:.55rem;align-items:center;flex-wrap:wrap}
      .lmc-source a{display:inline-flex;align-items:center;padding:.55rem .8rem;border:1px solid #cfd8e3;border-radius:10px;text-decoration:none;color:#172033;background:#fff;font-weight:700}
      .lmc-list{display:grid;gap:.65rem;overflow:auto;max-height:50vh;padding-right:.2rem}
      .lmc-row{border:1px solid #dfe5ec;border-radius:13px;padding:.85rem;display:grid;gap:.45rem}
      .lmc-row-head{display:flex;justify-content:space-between;gap:1rem;align-items:baseline}
      .lmc-row p,.lmc-row small{margin:0}
      .lmc-row small{color:#5d6878}
      .lmc-row a{justify-self:start;margin-top:.2rem;color:#0f766e;font-weight:700;text-decoration:none}
      .lmc-loading,.lmc-error{padding:1rem 0}
      .lmc-error{color:#9b1c1c}
      @media(max-width:640px){.lmc-row-head{flex-direction:column;gap:.2rem;align-items:flex-start}}
    `;
    document.head.append(style);
  }

  async function refreshInventory() {
    try {
      const [inventoryResponse, settingsResponse] = await Promise.all([
        fetch("/api/inventory", { credentials: "same-origin" }),
        fetch("/api/settings", { credentials: "same-origin" })
      ]);
      if (inventoryResponse.ok) {
        const store = await inventoryResponse.json();
        inventory = [...(store.vehicles || []), ...(store.removed || [])];
      }
      if (settingsResponse.ok) settings = await settingsResponse.json();
    } catch {}
  }

  function text(value) {
    return String(value || "").trim();
  }

  function normalized(value) {
    return text(value).toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
  }

  function number(value) {
    const n = Number(text(value).replace(/[^0-9.-]/g, ""));
    return Number.isFinite(n) ? n : 0;
  }

  function money(value) {
    const n = number(value);
    return n ? n.toLocaleString("en-US", { style: "currency", currency: "USD", maximumFractionDigits: 0 }) : "N/A";
  }

  function conditionOf(vehicle) {
    const explicit = normalized(vehicle?.inventoryCondition || vehicle?.listingType || vehicle?.vehicleCondition);
    const title = normalized(vehicle?.title);
    if (/\b(certified|cpo|carbravo)\b/.test(`${explicit} ${title}`)) return "certified";
    if (/\bnew\b/.test(explicit) || /^new\b/.test(title)) return "new";
    if (/\bused\b/.test(explicit)) return "used";
    return "used";
  }

  function cardFacts(card) {
    const facts = {};
    for (const wrapper of card.querySelectorAll(".facts > div")) {
      const key = normalized(wrapper.querySelector("dt")?.textContent);
      const value = text(wrapper.querySelector("dd")?.textContent);
      if (key) facts[key] = value;
    }
    return facts;
  }

  function vehicleForCard(card) {
    const title = text(card.querySelector("h2")?.textContent);
    const facts = cardFacts(card);
    const vin = normalized(facts.vin);
    if (vin && vin !== "n a") {
      const byVin = inventory.find((item) => normalized(item.vin) === vin);
      if (byVin) return byVin;
    }
    const byTitle = inventory.find((item) => normalized(item.title) === normalized(title));
    if (byTitle) return byTitle;
    return {
      title,
      mileage: facts.mileage,
      vin: facts.vin,
      stock: facts.stock,
      price: facts["verified posting price"] || facts["price not verified"] || ""
    };
  }

  function inferIdentity(vehicle) {
    const result = { ...vehicle };
    const words = text(vehicle.title).split(/\s+/).filter(Boolean);
    if (!result.year && /^(19|20)\d{2}$/.test(words[0] || "")) result.year = words[0];
    if (!result.make && words.length > 1) result.make = words[1];
    if (!result.model && words.length > 2) result.model = words[2];
    if (!result.trim && words.length > 3) result.trim = words.slice(3).join(" ");
    return result;
  }

  function applyConditionFilter() {
    const select = document.getElementById(FILTER_ID);
    const selected = select?.value || "all";
    for (const card of document.querySelectorAll(".vehicle-card")) {
      const vehicle = vehicleForCard(card);
      card.style.display = selected === "all" || conditionOf(vehicle) === selected ? "" : "none";
    }
  }

  function ensureConditionFilter() {
    const filters = document.querySelector(".filters");
    if (!filters || document.getElementById(FILTER_ID)) return;
    const select = document.createElement("select");
    select.id = FILTER_ID;
    select.setAttribute("aria-label", "Filter inventory by vehicle condition");
    [["all","All inventory"],["new","New"],["used","Used"],["certified","Certified"]].forEach(([value,label]) => select.add(new Option(label, value)));
    select.addEventListener("change", applyConditionFilter);
    filters.append(select);
  }

  function ensureDialog() {
    let dialog = document.getElementById(DIALOG_ID);
    if (dialog) return dialog;
    dialog = document.createElement("dialog");
    dialog.id = DIALOG_ID;
    dialog.innerHTML = `<div class="lmc-shell"><div class="lmc-header"><div><p class="lmc-eyebrow">Market Compare</p><h2>Vehicle Market Position</h2></div><button class="lmc-close" type="button" aria-label="Close">×</button></div><p class="lmc-note">LotCaster compares similar dealer listings returned through the connected browser helper. Verify individual listings before quoting a customer.</p><div class="lmc-body"></div></div>`;
    dialog.querySelector(".lmc-close").addEventListener("click", () => dialog.close());
    dialog.addEventListener("click", (event) => { if (event.target === dialog) dialog.close(); });
    document.body.append(dialog);
    return dialog;
  }

  function slug(value) {
    return text(value).toLowerCase().replace(/&/g, "and").replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
  }

  function marketZip() {
    const saved = localStorage.getItem("lotcasterMarketZip");
    if (/^\d{5}$/.test(saved || "")) return saved;
    if (/walker chevrolet/i.test(settings?.dealershipName || "")) {
      localStorage.setItem("lotcasterMarketZip", "37067");
      return "37067";
    }
    const entered = window.prompt("Enter the dealership ZIP code for market comparisons:", "") || "";
    const zip = entered.replace(/\D/g, "").slice(0, 5);
    if (/^\d{5}$/.test(zip)) {
      localStorage.setItem("lotcasterMarketZip", zip);
      return zip;
    }
    return "";
  }

  function buildSearchUrl(rawVehicle) {
    const vehicle = inferIdentity(rawVehicle);
    const zip = marketZip();
    if (!zip) throw new Error("A five-digit dealership ZIP is required for market comparison.");
    const year = text(vehicle.year).match(/\d{4}/)?.[0] || "";
    const make = slug(vehicle.make);
    const model = slug(vehicle.model);
    if (!year || !make || !model) throw new Error("LotCaster needs year, make, and model before it can compare this vehicle.");
    const type = conditionOf(vehicle);
    const listingType = type === "new" ? "NEW" : type === "certified" ? "CERTIFIED" : "USED";
    const url = new URL(`https://www.autotrader.com/cars-for-sale/${make}/${model}/${zip}`);
    url.searchParams.set("listingType", listingType);
    url.searchParams.set("searchRadius", "200");
    url.searchParams.set("startYear", year);
    url.searchParams.set("endYear", year);
    return url.href;
  }

  function helperCompare(url) {
    return new Promise((resolve, reject) => {
      if (!globalThis.chrome?.runtime?.id || typeof chrome.runtime.sendMessage !== "function") {
        reject(new Error("The LotCaster browser helper is not connected."));
        return;
      }
      chrome.runtime.sendMessage({ type: "lotcaster-market-compare", url }, (result) => {
        const runtimeError = chrome.runtime.lastError;
        if (runtimeError) return reject(new Error(runtimeError.message));
        if (!result) return reject(new Error("The browser helper returned no comparison data."));
        if (result.error) return reject(new Error(result.error));
        resolve(result);
      });
    });
  }

  function trimMatch(a, b) {
    const left = normalized(a);
    const right = normalized(b);
    if (!left || !right) return false;
    return left === right || left.startsWith(`${right} `) || right.startsWith(`${left} `);
  }

  function sameIdentity(subject, comp) {
    return normalized(subject.make) === normalized(comp.make)
      && normalized(subject.model) === normalized(comp.model)
      && text(subject.year) === text(comp.year);
  }

  function tierFor(subject, comp) {
    if (!sameIdentity(subject, comp)) return 99;
    const exactTrim = trimMatch(subject.trim, comp.trim);
    if (conditionOf(subject) === "new") return exactTrim ? 1 : 3;
    const subjectMiles = number(subject.mileage);
    const compMiles = number(comp.mileage);
    const delta = subjectMiles && compMiles ? Math.abs(subjectMiles - compMiles) : Number.MAX_SAFE_INTEGER;
    if (exactTrim && delta <= 5000) return 1;
    if (exactTrim && delta <= 10000) return 2;
    if (exactTrim) return 3;
    return 4;
  }

  function analyze(rawSubject, rawListings) {
    const subject = inferIdentity(rawSubject);
    const subjectVin = normalized(subject.vin);
    const seen = new Set();
    const comps = [];
    for (const raw of Array.isArray(rawListings) ? rawListings : []) {
      const comp = inferIdentity(raw);
      if (!sameIdentity(subject, comp)) continue;
      if (subjectVin && normalized(comp.vin) === subjectVin) continue;
      const compPrice = number(comp.price);
      if (!compPrice) continue;
      const key = normalized(comp.vin || comp.listingId || `${comp.title}|${comp.price}|${comp.mileage}|${comp.dealer}`);
      if (!key || seen.has(key)) continue;
      seen.add(key);
      const tier = tierFor(subject, comp);
      comps.push({ ...comp, tier, priceNumber: compPrice, mileageNumber: number(comp.mileage), mileageDelta: Math.abs(number(subject.mileage) - number(comp.mileage)) });
    }
    comps.sort((a,b) => (a.tier-b.tier) || (a.mileageDelta-b.mileageDelta) || (Math.abs(a.priceNumber-number(subject.price))-Math.abs(b.priceNumber-number(subject.price))));
    const top = comps.slice(0, 12);
    let statistical = top.filter((item) => item.tier <= 2);
    if (statistical.length < 3) statistical = top.filter((item) => item.tier <= 3);
    if (statistical.length < 3) statistical = top;
    const prices = statistical.map((item) => item.priceNumber).sort((a,b) => a-b);
    const median = prices.length ? (prices.length % 2 ? prices[(prices.length-1)/2] : (prices[prices.length/2-1]+prices[prices.length/2])/2) : 0;
    const average = prices.length ? prices.reduce((a,b)=>a+b,0)/prices.length : 0;
    const exact = top.filter((item) => item.tier === 1).length;
    const strong = top.filter((item) => item.tier <= 2).length;
    const confidence = Math.min(100, Math.round(exact*12 + Math.max(0,strong-exact)*7 + Math.max(0,top.length-strong)*2));
    return { subject, comps: top, stats: { count: statistical.length, low: prices[0] || 0, high: prices.at(-1) || 0, median, average, exact, strong, confidence } };
  }

  function renderComparison(dialog, result, sourceUrl) {
    const { subject, comps, stats } = result;
    dialog.querySelector("h2").textContent = subject.title || "Vehicle Market Position";
    const ourPrice = number(subject.price);
    const delta = stats.median && ourPrice ? ourPrice - stats.median : 0;
    const position = !stats.median || !ourPrice ? "Unavailable" : delta < -500 ? `${money(Math.abs(delta))} below median` : delta > 500 ? `${money(Math.abs(delta))} above median` : "Within $500 of market median";
    const body = dialog.querySelector(".lmc-body");
    body.replaceChildren();

    const summary = document.createElement("div");
    summary.className = "lmc-summary";
    [["Your price",money(ourPrice)],["Market median",money(stats.median)],["Market average",money(stats.average)],["Range",stats.count?`${money(stats.low)} – ${money(stats.high)}`:"No qualified comps"],["Position",position],["Confidence",`${stats.confidence}%`]].forEach(([label,value]) => {
      const card = document.createElement("div");
      const small = document.createElement("small");
      const strong = document.createElement("strong");
      small.textContent = label;
      strong.textContent = value;
      card.append(small,strong);
      summary.append(card);
    });

    const meta = document.createElement("p");
    meta.className = "lmc-meta";
    meta.textContent = `${comps.length} comparable listings · ${stats.exact} exact Tier 1 · ${stats.strong} Tier 1–2. Used Tier 1 requires exact trim and ±5,000 miles; new vehicles do not use mileage.`;

    const source = document.createElement("div");
    source.className = "lmc-source";
    const link = document.createElement("a");
    link.href = sourceUrl;
    link.target = "_blank";
    link.rel = "noreferrer";
    link.textContent = "Open AutoTrader Search";
    source.append(link);

    const list = document.createElement("div");
    list.className = "lmc-list";
    for (const comp of comps) {
      const row = document.createElement("article");
      row.className = "lmc-row";
      const head = document.createElement("div");
      head.className = "lmc-row-head";
      const title = document.createElement("strong");
      const price = document.createElement("strong");
      title.textContent = comp.title || [comp.year,comp.make,comp.model,comp.trim].filter(Boolean).join(" ");
      price.textContent = money(comp.price);
      head.append(title,price);
      const detail = document.createElement("p");
      detail.textContent = [`Tier ${comp.tier}`, comp.mileageNumber ? `${comp.mileageNumber.toLocaleString()} mi` : "", comp.dealer, comp.distance ? `${comp.distance} away` : "", comp.fuelType, comp.driveType, comp.engine, comp.transmission].filter(Boolean).join(" · ");
      const feature = document.createElement("small");
      const features = Array.isArray(comp.features) ? comp.features.filter(Boolean).slice(0,8) : [];
      feature.textContent = features.length ? `Features: ${features.join(", ")}` : "Feature details not exposed in this result.";
      row.append(head,detail,feature);
      if (comp.url) {
        const compLink = document.createElement("a");
        compLink.href = comp.url;
        compLink.target = "_blank";
        compLink.rel = "noreferrer";
        compLink.textContent = "Open Comp";
        row.append(compLink);
      }
      list.append(row);
    }
    if (!comps.length) {
      const empty = document.createElement("p");
      empty.className = "lmc-meta";
      empty.textContent = "The search loaded, but no same-year/make/model listings met the comparison rules.";
      list.append(empty);
    }
    body.append(summary,meta,source,list);
  }

  async function openCompare(vehicle, button) {
    const dialog = ensureDialog();
    const body = dialog.querySelector(".lmc-body");
    dialog.querySelector("h2").textContent = vehicle.title || "Vehicle Market Position";
    body.innerHTML = `<div class="lmc-loading"><strong>Loading comparable market listings…</strong><p>LotCaster is opening a targeted AutoTrader search through the browser helper.</p></div>`;
    dialog.showModal();
    const original = button.textContent;
    button.disabled = true;
    button.textContent = "Comparing…";
    try {
      await refreshInventory();
      const current = inventory.find((item) => normalized(item.vin) === normalized(vehicle.vin)) || vehicle;
      const url = buildSearchUrl(current);
      const helperResult = await helperCompare(url);
      const analysis = analyze(current, helperResult.listings || []);
      renderComparison(dialog, analysis, helperResult.url || url);
    } catch (error) {
      body.innerHTML = `<div class="lmc-error"><strong>Comparison failed</strong><p></p></div>`;
      body.querySelector("p").textContent = error.message || String(error);
    } finally {
      button.disabled = false;
      button.textContent = original;
    }
  }

  function enhanceCards() {
    for (const card of document.querySelectorAll(".vehicle-card")) {
      const actions = card.querySelector(".card-actions");
      if (!actions || actions.querySelector(".lotcaster-market-button")) continue;
      const button = document.createElement("button");
      button.type = "button";
      button.className = "secondary lotcaster-market-button";
      button.textContent = "Compare Market";
      button.addEventListener("click", () => openCompare(vehicleForCard(card), button));
      const posted = actions.querySelector(".posted-toggle");
      actions.insertBefore(button, posted || actions.firstChild);
    }
    applyConditionFilter();
  }

  async function boot() {
    injectStyles();
    await refreshInventory();
    ensureConditionFilter();
    ensureDialog();
    enhanceCards();
    observer = new MutationObserver(() => {
      ensureConditionFilter();
      enhanceCards();
    });
    observer.observe(document.documentElement, { subtree: true, childList: true });
    window.addEventListener("focus", refreshInventory);
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot, { once: true });
  else boot();
})();

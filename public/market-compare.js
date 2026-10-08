// LotCaster Market Compare v1
(() => {
  const market = {
    store: { vehicles: [] },
    settings: {},
    condition: "all",
    zip: localStorage.getItem("lotcasterMarketZip") || "37067",
    dialog: null,
    body: null,
    title: null,
    refreshTimer: null
  };

  const moneyNumber = (value) => {
    const parsed = Number(String(value ?? "").replace(/[^0-9.-]/g, ""));
    return Number.isFinite(parsed) ? parsed : 0;
  };

  const money = (value) => {
    const amount = moneyNumber(value);
    return amount ? amount.toLocaleString("en-US", { style: "currency", currency: "USD", maximumFractionDigits: 0 }) : "N/A";
  };

  const clean = (value) => String(value || "").toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
  const slug = (value) => String(value || "").trim().toLowerCase().replace(/&/g, "and").replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");

  function conditionOf(vehicle) {
    const value = clean(vehicle?.inventoryCondition || vehicle?.listingType || "");
    const title = clean(vehicle?.title);
    if (/certified|cpo|carbravo/.test(value) || /certified|cpo|carbravo/.test(title)) return "certified";
    if (/\bnew\b/.test(value)) return "new";
    if (/\bused\b/.test(value)) return "used";
    return "used";
  }

  function displayCondition(vehicle) {
    const value = conditionOf(vehicle);
    return value === "certified" ? "Certified" : value === "new" ? "New" : "Used";
  }

  async function api(url) {
    const response = await fetch(url, { headers: { "content-type": "application/json" } });
    if (!response.ok) throw new Error(`Request failed with HTTP ${response.status}`);
    return response.json();
  }

  async function refreshData() {
    try {
      const [store, settings] = await Promise.all([api("/api/inventory"), api("/api/settings")]);
      market.store = store || { vehicles: [] };
      market.settings = settings || {};
      annotateCards();
    } catch (error) {
      console.warn("Market Compare could not refresh inventory context", error);
    }
  }

  function readFact(card, label) {
    const wanted = clean(label);
    for (const row of card.querySelectorAll(".facts > div")) {
      const dt = row.querySelector("dt");
      const dd = row.querySelector("dd");
      if (clean(dt?.textContent) === wanted) return String(dd?.textContent || "").trim();
    }
    return "";
  }

  function vehicleForCard(card) {
    const title = String(card.querySelector("h2")?.textContent || "").trim();
    const vin = readFact(card, "VIN");
    const stock = readFact(card, "Stock");
    const vehicles = market.store?.vehicles || [];
    return vehicles.find((vehicle) => vin && clean(vehicle.vin) === clean(vin))
      || vehicles.find((vehicle) => stock && clean(vehicle.stock) === clean(stock))
      || vehicles.find((vehicle) => clean(vehicle.title) === clean(title))
      || null;
  }

  function addConditionFact(card, vehicle) {
    const facts = card.querySelector(".facts");
    if (!facts || facts.querySelector('[data-market-condition="1"]')) return;
    const row = document.createElement("div");
    row.dataset.marketCondition = "1";
    const dt = document.createElement("dt");
    const dd = document.createElement("dd");
    dt.textContent = "Inventory";
    dd.textContent = displayCondition(vehicle);
    row.append(dt, dd);
    facts.append(row);
  }

  function annotateCards() {
    document.querySelectorAll("#vehicleGrid .vehicle-card").forEach((card) => {
      const vehicle = vehicleForCard(card);
      if (!vehicle) return;
      card.dataset.inventoryCondition = conditionOf(vehicle);
      addConditionFact(card, vehicle);

      const actions = card.querySelector(".card-actions");
      if (actions && !actions.querySelector(".market-compare-button")) {
        const button = document.createElement("button");
        button.type = "button";
        button.className = "secondary market-compare-button";
        button.textContent = "Compare Market";
        button.addEventListener("click", () => openComparison(vehicle, button));
        const posted = actions.querySelector(".posted-toggle");
        actions.insertBefore(button, posted || actions.firstChild);
      }
      card.hidden = market.condition !== "all" && card.dataset.inventoryCondition !== market.condition;
    });
  }

  function setupControls() {
    const filters = document.querySelector(".filters");
    if (!filters || document.querySelector("#conditionFilter")) return;

    const select = document.createElement("select");
    select.id = "conditionFilter";
    select.setAttribute("aria-label", "Filter inventory by vehicle condition");
    [["all", "All inventory"], ["new", "New"], ["used", "Used"], ["certified", "Certified"]]
      .forEach(([value, label]) => select.add(new Option(label, value)));
    select.addEventListener("change", () => {
      market.condition = select.value;
      annotateCards();
    });

    const zip = document.createElement("input");
    zip.id = "marketZip";
    zip.className = "market-zip-input";
    zip.inputMode = "numeric";
    zip.maxLength = 5;
    zip.placeholder = "Market ZIP";
    zip.title = "ZIP used for Market Compare searches";
    zip.value = market.zip;
    zip.addEventListener("change", () => {
      const value = String(zip.value || "").replace(/\D/g, "").slice(0, 5);
      market.zip = value || "37067";
      zip.value = market.zip;
      localStorage.setItem("lotcasterMarketZip", market.zip);
    });

    filters.append(select, zip);
  }

  function setupDialog() {
    if (market.dialog) return;
    const dialog = document.createElement("dialog");
    dialog.id = "marketCompareDialog";
    dialog.className = "posting-dialog market-compare-dialog";
    dialog.innerHTML = `
      <div class="posting-header">
        <div>
          <p class="eyebrow">Market Compare</p>
          <h2 id="marketCompareTitle">Vehicle Market Position</h2>
        </div>
        <button id="closeMarketCompareButton" class="icon-button" type="button" aria-label="Close market comparison">&times;</button>
      </div>
      <p class="posting-note">LotCaster compares similar dealer listings returned through the connected browser helper. Market listings can change at any time; verify individual vehicles before quoting a customer.</p>
      <div id="marketCompareBody" class="market-compare-body"></div>`;
    document.body.append(dialog);
    market.dialog = dialog;
    market.body = dialog.querySelector("#marketCompareBody");
    market.title = dialog.querySelector("#marketCompareTitle");
    dialog.querySelector("#closeMarketCompareButton").addEventListener("click", () => dialog.close());
    dialog.addEventListener("click", (event) => { if (event.target === dialog) dialog.close(); });
  }

  function buildSearchUrl(vehicle) {
    const year = String(vehicle.year || "").match(/\d{4}/)?.[0] || "";
    const make = slug(vehicle.make);
    const model = slug(vehicle.model);
    const condition = conditionOf(vehicle);
    const listingType = condition === "new" ? "NEW" : condition === "certified" ? "CERTIFIED" : "USED";
    const path = [year, make, model].filter(Boolean).join("/");
    const url = new URL(`https://www.autotrader.com/cars-for-sale/${path}`);
    url.searchParams.set("listingType", listingType);
    url.searchParams.set("searchRadius", "200");
    url.searchParams.set("zip", market.zip || "37067");
    if (year) {
      url.searchParams.set("startYear", year);
      url.searchParams.set("endYear", year);
    }
    return url.href;
  }

  function requestMarket(vehicle) {
    return new Promise((resolve, reject) => {
      const requestId = crypto.randomUUID();
      const timeout = setTimeout(() => {
        window.removeEventListener("message", onMessage);
        reject(new Error("The browser helper did not return market listings. Reload the LotCaster helper extension and try again."));
      }, 70000);
      function onMessage(event) {
        if (event.source !== window || event.data?.type !== "lotcaster-market-compare-result" || event.data.requestId !== requestId) return;
        clearTimeout(timeout);
        window.removeEventListener("message", onMessage);
        if (event.data.error) reject(new Error(event.data.error));
        else resolve(event.data);
      }
      window.addEventListener("message", onMessage);
      window.postMessage({ type: "lotcaster-market-compare", requestId, url: buildSearchUrl(vehicle) }, window.location.origin);
    });
  }

  function trimMatch(a, b) {
    const left = clean(a);
    const right = clean(b);
    if (!left || !right) return false;
    return left === right || left.startsWith(`${right} `) || right.startsWith(`${left} `);
  }

  function identityMatch(subject, comp) {
    return clean(subject.make) === clean(comp.make)
      && clean(subject.model) === clean(comp.model)
      && String(subject.year || "") === String(comp.year || "");
  }

  function tier(subject, comp) {
    if (!identityMatch(subject, comp)) return 99;
    const exactTrim = trimMatch(subject.trim, comp.trim);
    if (conditionOf(subject) === "new") return exactTrim ? 1 : 3;
    const subjectMiles = moneyNumber(subject.mileage);
    const compMiles = moneyNumber(comp.mileage);
    const delta = subjectMiles && compMiles ? Math.abs(subjectMiles - compMiles) : Number.MAX_SAFE_INTEGER;
    if (exactTrim && delta <= 5000) return 1;
    if (exactTrim && delta <= 10000) return 2;
    if (exactTrim) return 3;
    return 4;
  }

  function analyze(subject, rawListings) {
    const subjectVin = clean(subject.vin);
    const seen = new Set();
    const comps = [];
    for (const raw of Array.isArray(rawListings) ? rawListings : []) {
      if (!identityMatch(subject, raw)) continue;
      if (subjectVin && clean(raw.vin) === subjectVin) continue;
      const price = moneyNumber(raw.price);
      if (!price) continue;
      const key = clean(raw.vin || raw.listingId || `${raw.title}|${raw.price}|${raw.mileage}|${raw.dealer}`);
      if (!key || seen.has(key)) continue;
      seen.add(key);
      const t = tier(subject, raw);
      comps.push({ ...raw, priceNumber: price, mileageNumber: moneyNumber(raw.mileage), tier: t, mileageDelta: Math.abs(moneyNumber(subject.mileage) - moneyNumber(raw.mileage)) });
    }
    comps.sort((a, b) => (a.tier - b.tier) || (a.mileageDelta - b.mileageDelta) || (Math.abs(a.priceNumber - moneyNumber(subject.price)) - Math.abs(b.priceNumber - moneyNumber(subject.price))));
    const top = comps.slice(0, 12);
    let statistical = top.filter((item) => item.tier <= 2);
    if (statistical.length < 3) statistical = top.filter((item) => item.tier <= 3);
    if (statistical.length < 3) statistical = top;
    const prices = statistical.map((item) => item.priceNumber).sort((a, b) => a - b);
    const median = prices.length ? (prices.length % 2 ? prices[(prices.length - 1) / 2] : (prices[prices.length / 2 - 1] + prices[prices.length / 2]) / 2) : 0;
    const average = prices.length ? prices.reduce((sum, value) => sum + value, 0) / prices.length : 0;
    const exact = top.filter((item) => item.tier === 1).length;
    const strong = top.filter((item) => item.tier <= 2).length;
    return {
      comps: top,
      stats: {
        count: statistical.length,
        low: prices[0] || 0,
        high: prices.at(-1) || 0,
        median,
        average,
        exact,
        strong,
        confidence: Math.min(100, Math.round(exact * 12 + Math.max(0, strong - exact) * 7 + Math.max(0, top.length - strong) * 2))
      }
    };
  }

  function renderComparison(subject, analysis, sourceUrl) {
    const { comps, stats } = analysis;
    const ourPrice = moneyNumber(subject.price);
    const delta = stats.median && ourPrice ? ourPrice - stats.median : 0;
    const position = !stats.median || !ourPrice ? "Market position unavailable"
      : delta < -500 ? `${money(Math.abs(delta))} below median`
      : delta > 500 ? `${money(Math.abs(delta))} above median`
      : "Within $500 of market median";

    const summary = document.createElement("section");
    summary.className = "market-summary-grid";
    [["Your price", money(ourPrice)], ["Market median", money(stats.median)], ["Market average", money(stats.average)], ["Range", stats.count ? `${money(stats.low)} – ${money(stats.high)}` : "No qualified comps"], ["Position", position], ["Confidence", `${stats.confidence}%`]]
      .forEach(([label, value]) => {
        const card = document.createElement("div");
        const small = document.createElement("small");
        const strong = document.createElement("strong");
        small.textContent = label;
        strong.textContent = value;
        card.append(small, strong);
        summary.append(card);
      });

    const meta = document.createElement("p");
    meta.className = "market-compare-meta";
    meta.textContent = `${comps.length} comparable listings found · ${stats.exact} exact Tier 1 · ${stats.strong} Tier 1–2 · Used vehicles prioritize exact trim within ±5,000 miles; new vehicles ignore mileage.`;

    const source = document.createElement("a");
    source.className = "secondary";
    source.target = "_blank";
    source.rel = "noreferrer";
    source.href = sourceUrl || buildSearchUrl(subject);
    source.textContent = "Open AutoTrader Search";

    const list = document.createElement("div");
    list.className = "market-comp-list";
    for (const comp of comps) {
      const row = document.createElement("article");
      row.className = "market-comp-row";
      const header = document.createElement("div");
      const title = document.createElement("strong");
      const price = document.createElement("strong");
      title.textContent = comp.title || [comp.year, comp.make, comp.model, comp.trim].filter(Boolean).join(" ");
      price.textContent = money(comp.price);
      header.append(title, price);
      const details = document.createElement("p");
      details.textContent = [`Tier ${comp.tier}`, comp.mileage ? `${Number(comp.mileageNumber).toLocaleString()} mi` : "", comp.dealer, comp.distance ? `${comp.distance} away` : "", comp.fuelType, comp.driveType, comp.engine, comp.transmission].filter(Boolean).join(" · ");
      const features = document.createElement("small");
      const featureList = Array.isArray(comp.features) ? comp.features.filter(Boolean).slice(0, 8) : [];
      features.textContent = featureList.length ? `Features: ${featureList.join(", ")}` : "Feature details not exposed in this result.";
      row.append(header, details, features);
      if (comp.url) {
        const link = document.createElement("a");
        link.className = "secondary compact-button";
        link.target = "_blank";
        link.rel = "noreferrer";
        link.href = comp.url;
        link.textContent = "Open Comp";
        row.append(link);
      }
      list.append(row);
    }
    market.body.replaceChildren(summary, meta, source, list);
  }

  async function openComparison(vehicle, button) {
    setupDialog();
    market.title.textContent = vehicle.title || "Vehicle Market Position";
    market.body.innerHTML = '<div class="market-loading"><strong>Loading comparable market listings…</strong><p>LotCaster is opening a targeted AutoTrader search through the browser helper.</p></div>';
    market.dialog.showModal();
    const original = button.textContent;
    button.disabled = true;
    button.textContent = "Comparing…";
    try {
      const result = await requestMarket(vehicle);
      const analysis = analyze(vehicle, result.listings || []);
      renderComparison(vehicle, analysis, result.url);
    } catch (error) {
      const wrap = document.createElement("div");
      wrap.className = "market-loading market-error";
      const strong = document.createElement("strong");
      const p = document.createElement("p");
      strong.textContent = "Comparison failed";
      p.textContent = String(error.message || error);
      wrap.append(strong, p);
      market.body.replaceChildren(wrap);
    } finally {
      button.disabled = false;
      button.textContent = original;
    }
  }

  function watchGrid() {
    const grid = document.querySelector("#vehicleGrid");
    if (!grid) return;
    new MutationObserver(() => {
      clearTimeout(market.refreshTimer);
      market.refreshTimer = setTimeout(refreshData, 120);
    }).observe(grid, { childList: true });
  }

  async function init() {
    setupControls();
    setupDialog();
    watchGrid();
    await refreshData();
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init, { once: true });
  else init();
})();

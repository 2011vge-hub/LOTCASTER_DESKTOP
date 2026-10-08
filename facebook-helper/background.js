chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message?.type === "lotcaster-fetch-inventory-source" && message.url) {
    captureRenderedInventory(message.url)
      .then(sendResponse)
      .catch((error) => sendResponse({ error: error.message }));
    return true;
  }
  if (message?.type === "lotcaster-market-compare" && message.url) {
    captureMarketComparison(message.url)
      .then(sendResponse)
      .catch((error) => sendResponse({ error: error.message }));
    return true;
  }
  if (message?.type !== "walker-fetch-image" || !message.url) return;
  fetch(message.url)
    .then((response) => {
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const contentType = response.headers.get("content-type") || "";
      if (!/^image\/(?:jpeg|png|webp)(?:;|$)/i.test(contentType)) {
        throw new Error(`Not an image (${contentType || "unknown content type"})`);
      }
      return response.arrayBuffer().then((buffer) => {
        if (buffer.byteLength > 15 * 1024 * 1024) throw new Error("Image exceeds the 15 MB transfer limit.");
        return { bytes: Array.from(new Uint8Array(buffer)), contentType };
      });
    })
    .then(sendResponse)
    .catch((error) => sendResponse({ error: error.message }));
  return true;
});

async function captureRenderedInventory(url) {
  const sourceTabs = [];
  try {
    const sourceUrl = new URL(url);
    const configuredDealerId = sourceUrl.pathname.match(/\/car-dealers\/[^/]+\/(\d+)\//i)?.[1] || "";
    if (/(^|\.)autotrader\.com$/i.test(sourceUrl.hostname)) {
      // AutoTrader began redirecting dealer pages with numRecords=100 to the
      // generic city dealer directory. Load the normal 25-record dealer pages
      // instead and combine them before sending them back to LotCaster.
      sourceUrl.searchParams.delete("numRecords");
      sourceUrl.searchParams.delete("firstRecord");
      // Walker previously stored a used-only dealer URL. Market Compare needs
      // the same inventory workspace to contain all retail conditions, so the
      // helper upgrades Walker's request even on the first refresh after the
      // feature is installed.
      if (configuredDealerId === "100009092") {
        sourceUrl.searchParams.set("listingType", "NEW,USED,CERTIFIED");
      }
    }

    const pages = [];
    const pageSize = 25;
    const maxPages = configuredDealerId ? 4 : 1;
    for (let pageIndex = 0; pageIndex < maxPages; pageIndex += 1) {
      const pageUrl = new URL(sourceUrl.href);
      if (pageIndex > 0) pageUrl.searchParams.set("firstRecord", String(pageIndex * pageSize));
      const sourceTab = await chrome.tabs.create({ url: pageUrl.href, active: false });
      sourceTabs.push(sourceTab);
      await waitForTab(sourceTab.id, 45000);
      const results = await chrome.scripting.executeScript({
        target: { tabId: sourceTab.id },
        func: () => {
          const nextData = document.querySelector("#__NEXT_DATA__");
          if (/(^|\.)autotrader\.com$/i.test(location.hostname) && nextData?.textContent) {
            let inventoryCount = 0;
            try {
              const data = JSON.parse(nextData.textContent);
              inventoryCount = Object.keys(data?.props?.pageProps?.__eggsState?.inventory || {}).length;
            } catch {}
            return { url: location.href, html: nextData.outerHTML, inventoryCount };
          }
          const cards = [...document.querySelectorAll(".vehicle-card-body")];
          return { url: location.href, html: cards.map((card) => card.outerHTML).join("\n"), inventoryCount: cards.length };
        }
      });
      const result = results?.[0]?.result;
      if (configuredDealerId) {
        const finalUrl = new URL(result?.url || sourceTab.url || pageUrl.href);
        if (!finalUrl.pathname.includes(`/${configuredDealerId}/`)) {
          throw new Error("AutoTrader redirected the configured dealership link to a generic search page. LotCaster retried the canonical dealer pages but could not verify the dealership identity.");
        }
      }
      if (!result?.html) {
        if (pageIndex === 0) throw new Error("The inventory page loaded, but no structured inventory records were found.");
        break;
      }
      pages.push({ url: result.url || pageUrl.href, html: result.html });
      if (Number(result.inventoryCount || 0) < pageSize) break;
    }
    if (!pages.length) throw new Error("The inventory page loaded, but no structured inventory records were found.");
    return { url: pages[0].url, html: pages[0].html, pages };
  } finally {
    await Promise.all(sourceTabs.map((tab) => tab?.id ? chrome.tabs.remove(tab.id).catch(() => {}) : null));
  }
}

async function captureMarketComparison(url) {
  let marketTab = null;
  try {
    marketTab = await chrome.tabs.create({ url, active: false });
    await waitForTab(marketTab.id, 45000);
    // Give client-rendered inventory state a short moment to settle after the
    // browser reports the initial document complete.
    await new Promise((resolve) => setTimeout(resolve, 1200));
    const results = await chrome.scripting.executeScript({
      target: { tabId: marketTab.id },
      func: () => {
        function text(value) {
          if (value == null) return "";
          if (typeof value === "string" || typeof value === "number") return String(value).trim();
          if (typeof value === "object") return text(value.name ?? value.label ?? value.value ?? "");
          return "";
        }
        function number(value) {
          const found = text(value).replace(/[^0-9.]/g, "");
          return found ? Number(found) : 0;
        }
        function priceOf(item) {
          const candidates = [
            item?.pricingDetail?.salePrice,
            item?.pricingDetail?.displayPrice,
            item?.pricing?.salePrice,
            item?.pricing?.displayPrice,
            item?.salePrice,
            item?.displayPrice,
            item?.price
          ];
          for (const value of candidates) {
            const amount = number(value);
            if (amount > 0) return amount;
          }
          return 0;
        }
        function mileageOf(item) {
          const candidates = [item?.mileage, item?.odometer, item?.mileageFromOdometer?.value, item?.specifications?.mileage];
          for (const value of candidates) {
            const amount = number(value);
            if (amount > 0) return Math.round(amount);
          }
          return 0;
        }
        function collectFeatureStrings(value, depth = 0, out = new Set()) {
          if (depth > 4 || value == null || out.size > 30) return out;
          if (typeof value === "string") {
            const clean = value.trim();
            if (clean.length > 2 && clean.length < 90) out.add(clean);
            return out;
          }
          if (Array.isArray(value)) {
            value.forEach((item) => collectFeatureStrings(item, depth + 1, out));
            return out;
          }
          if (typeof value === "object") {
            Object.entries(value).forEach(([key, child]) => {
              if (/(feature|option|package|highlight|equipment|amenit)/i.test(key) || Array.isArray(child)) {
                collectFeatureStrings(child, depth + 1, out);
              }
            });
          }
          return out;
        }
        function dealerOf(item) {
          return text(item?.dealer?.name || item?.seller?.name || item?.dealerName || item?.owner?.name || item?.sellerName);
        }
        function itemUrl(item) {
          const raw = text(item?.url || item?.vehicleDetailsUrl || item?.vdpUrl || item?.permalink);
          try { return raw ? new URL(raw, location.origin).href : ""; } catch { return ""; }
        }

        const nextData = document.querySelector("#__NEXT_DATA__");
        if (!nextData?.textContent) {
          return { url: location.href, listings: [], error: "AutoTrader loaded, but structured market listing data was not available." };
        }
        let root;
        try {
          root = JSON.parse(nextData.textContent);
        } catch {
          return { url: location.href, listings: [], error: "AutoTrader market data could not be decoded." };
        }

        const queue = [root];
        const listings = [];
        const seen = new Set();
        let visited = 0;
        while (queue.length && visited < 60000 && listings.length < 150) {
          const node = queue.shift();
          visited += 1;
          if (!node || typeof node !== "object") continue;
          if (Array.isArray(node)) {
            node.forEach((child) => child && typeof child === "object" && queue.push(child));
            continue;
          }

          const vin = text(node.vin || node.VIN || node.vehicleIdentificationNumber);
          const year = text(node.year || node.modelYear);
          const make = text(node?.make?.name || node.make || node.makeName);
          const model = text(node?.model?.name || node.model || node.modelName);
          const hasIdentity = /^(19|20)\d{2}$/.test(year) && make && model;
          const hasListingSignal = vin.length === 17 || node.listingId || node.id || node.pricingDetail || node.salePrice || node.displayPrice;
          if (hasIdentity && hasListingSignal) {
            const listingId = text(node.listingId || node.id || vin || `${year}-${make}-${model}-${mileageOf(node)}-${priceOf(node)}`);
            if (listingId && !seen.has(listingId)) {
              seen.add(listingId);
              const trim = text(node?.trim?.name || node.trim || node?.atTrim?.name);
              const listingType = text(node.listingType || node.condition || node.inventoryType);
              const title = text(node.title || node.name || node.vehicleTitle) || [listingType, year, make, model, trim].filter(Boolean).join(" ");
              const features = [...collectFeatureStrings({
                features: node.features,
                options: node.options,
                packages: node.packages,
                highlights: node.highlights,
                specifications: node.specifications
              })].filter((value) => !/^(yes|no|true|false)$/i.test(value));
              listings.push({
                listingId,
                title,
                year,
                make,
                model,
                trim,
                listingType,
                price: priceOf(node),
                mileage: mileageOf(node),
                vin,
                dealer: dealerOf(node),
                distance: text(node.distance || node.distanceFromSearchLocation || node?.dealer?.distance),
                fuelType: text(node.fuelType || node.fuel || node?.specifications?.fuelType),
                driveType: text(node.driveType || node.drivetrain || node?.specifications?.driveType),
                engine: text(node.engine || node.engineDescription || node?.specifications?.engine),
                transmission: text(node.transmission || node?.specifications?.transmission),
                exteriorColor: text(node.exteriorColor || node?.color?.exteriorColor),
                interiorColor: text(node.interiorColor || node?.color?.interiorColor),
                features,
                url: itemUrl(node)
              });
              continue;
            }
          }

          Object.values(node).forEach((child) => {
            if (child && typeof child === "object") queue.push(child);
          });
        }
        return { url: location.href, listings };
      }
    });
    const result = results?.[0]?.result;
    if (!result) throw new Error("AutoTrader opened, but LotCaster could not read the market results.");
    if (result.error) throw new Error(result.error);
    return result;
  } finally {
    if (marketTab?.id) await chrome.tabs.remove(marketTab.id).catch(() => {});
  }
}

function waitForTab(tabId, timeoutMs) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => finish(new Error("The inventory website did not finish loading.")), timeoutMs);
    function finish(error) {
      clearTimeout(timeout);
      chrome.tabs.onUpdated.removeListener(onUpdated);
      error ? reject(error) : resolve();
    }
    function onUpdated(updatedId, changeInfo) {
      if (updatedId === tabId && changeInfo.status === "complete") finish();
    }
    chrome.tabs.onUpdated.addListener(onUpdated);
    chrome.tabs.get(tabId).then((tab) => { if (tab.status === "complete") finish(); }).catch(finish);
  });
}

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message?.type === "lotcaster-fetch-inventory-source" && message.url) {
    captureRenderedInventory(message.url)
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

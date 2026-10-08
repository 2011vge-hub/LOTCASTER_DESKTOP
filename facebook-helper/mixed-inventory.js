(() => {
  let busy = false;

  function isWalkerAutoTraderSource(value) {
    try {
      const url = new URL(String(value || ""));
      return /(^|\.)autotrader\.com$/i.test(url.hostname) && /\/100009092\//.test(url.pathname);
    } catch {
      return false;
    }
  }

  function currentSettings() {
    return {
      inventoryUrl: document.querySelector("#inventoryUrl")?.value || "",
      docFee: document.querySelector("#docFee")?.value || "",
      sourcePriceIncludesDocFee: Boolean(document.querySelector("#sourcePriceIncludesDocFee")?.checked),
      dealershipName: document.querySelector("#dealershipName")?.value || "",
      city: document.querySelector("#city")?.value || "",
      listingFooter: document.querySelector("#listingFooter")?.value || ""
    };
  }

  function helperInventory(url) {
    return new Promise((resolve, reject) => {
      if (!globalThis.chrome?.runtime?.id || typeof chrome.runtime.sendMessage !== "function") {
        reject(new Error("The LotCaster browser helper is not connected."));
        return;
      }
      chrome.runtime.sendMessage({ type: "lotcaster-fetch-inventory-source", url }, (result) => {
        const runtimeError = chrome.runtime.lastError;
        if (runtimeError) return reject(new Error(runtimeError.message));
        if (!result) return reject(new Error("The browser helper returned no inventory data."));
        if (result.error) return reject(new Error(result.error));
        resolve(result);
      });
    });
  }

  async function importMixedWalkerInventory(button) {
    if (busy) return;
    busy = true;
    const original = button.textContent;
    button.disabled = true;
    button.textContent = "Importing…";
    try {
      const settings = currentSettings();
      const source = await helperInventory(settings.inventoryUrl);
      const response = await fetch("/api/import-html", {
        method: "POST",
        credentials: "same-origin",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ ...settings, sourceUrl: source.url, html: source.html, pages: source.pages })
      });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || `Import failed with HTTP ${response.status}`);
      // The core LotCaster app owns in-memory inventory state, so reload after a
      // successful helper import to make its state and all UI counts consistent.
      window.location.reload();
    } catch (error) {
      button.disabled = false;
      button.textContent = original;
      const status = document.querySelector("#statusMessage");
      if (status) status.textContent = error.message || "Mixed inventory import failed.";
    } finally {
      busy = false;
    }
  }

  function onClick(event) {
    const button = event.target?.closest?.("#autoImportButton");
    if (!button) return;
    const inventoryUrl = document.querySelector("#inventoryUrl")?.value || "";
    if (!isWalkerAutoTraderSource(inventoryUrl)) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    importMixedWalkerInventory(button);
  }

  // Capture phase intentionally runs before LotCaster's existing click handler.
  // Non-Walker inventory sources are untouched and continue through the core app.
  document.addEventListener("click", onClick, true);
})();

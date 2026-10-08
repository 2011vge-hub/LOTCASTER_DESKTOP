function announceWalkerHelper() {
  if (!document.documentElement) {
    window.setTimeout(announceWalkerHelper, 50);
    return;
  }
  if (!globalThis.chrome?.runtime?.id || typeof globalThis.chrome.runtime.sendMessage !== "function") {
    delete document.documentElement.dataset.walkerFacebookHelper;
    return;
  }
  document.documentElement.dataset.walkerFacebookHelper = "1.9.0";
  window.postMessage({ type: "walker-facebook-helper-ready", version: "1.9.0" }, window.location.origin);
}

announceWalkerHelper();
window.addEventListener("walker-facebook-helper-check", announceWalkerHelper);
window.addEventListener("message", async (event) => {
  if (event.source !== window || event.data?.type !== "lotcaster-fetch-inventory-source") return;
  const { requestId, url } = event.data;
  try {
    if (!globalThis.chrome?.runtime?.id || typeof globalThis.chrome.runtime.sendMessage !== "function") {
      throw new Error("Extension context invalidated");
    }
    const result = await chrome.runtime.sendMessage({ type: "lotcaster-fetch-inventory-source", url });
    window.postMessage({ type: "lotcaster-inventory-source-result", requestId, ...result }, window.location.origin);
  } catch (error) {
    window.postMessage({ type: "lotcaster-inventory-source-result", requestId, error: error.message }, window.location.origin);
  }
});

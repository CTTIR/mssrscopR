// Shiny notifications are inserted after the page has loaded.
(() => {
  let lastOutsideFocus = null;
  let focusedDismissal = null;

  function usableFocusTarget(element) {
    if (!(element instanceof HTMLElement) || !element.isConnected ||
        element.tabIndex < 0 || element.matches(":disabled") ||
        element.closest('[inert], [aria-hidden="true"], [aria-disabled="true"]') ||
        !element.getClientRects().length) return false;
    const style = window.getComputedStyle(element);
    return style.visibility !== "hidden" && style.visibility !== "collapse";
  }

  function restoreRemovedDismissal() {
    if (!focusedDismissal || focusedDismissal.close.isConnected) return;
    const dismissal = focusedDismissal;
    focusedDismissal = null;
    // A later focus or pointer action belongs to the user. Only repair focus
    // lost when the focused close control itself disappears (including expiry).
    if (document.activeElement !== document.body &&
        document.activeElement !== document.documentElement) return;
    const candidates = [dismissal.previous,
      document.getElementById("compute"),
      document.querySelector('#tabs [role="tab"][aria-selected="true"]')];
    const target = candidates.find(usableFocusTarget);
    if (target) target.focus();
  }

  function prepareNotifications() {
    restoreRemovedDismissal();
    const panel = document.getElementById("shiny-notification-panel");
    if (!panel) return;
    panel.setAttribute("role", "region");
    panel.setAttribute("aria-label", "Notifications");
    panel.querySelectorAll(".shiny-notification-content-text").forEach((message) => {
      message.setAttribute("role", "alert");
      message.setAttribute("aria-atomic", "true");
    });
    panel.querySelectorAll(".shiny-notification-close").forEach((close) => {
      if (close.dataset.keyboardReady) return;
      close.dataset.keyboardReady = "true";
      close.setAttribute("role", "button");
      close.setAttribute("tabindex", "0");
      close.setAttribute("aria-label", "Dismiss notification");
      close.addEventListener("keydown", (event) => {
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault();
          close.click();
        }
      });
    });
  }
  document.addEventListener("DOMContentLoaded", () => {
    document.addEventListener("focusin", (event) => {
      const close = event.target.closest(".shiny-notification-close");
      focusedDismissal = close ? { close, previous: lastOutsideFocus } : null;
      if (!event.target.closest("#shiny-notification-panel") &&
          usableFocusTarget(event.target)) lastOutsideFocus = event.target;
    });
    document.addEventListener("pointerdown", () => {
      focusedDismissal = null;
    }, true);
    document.addEventListener("keydown", (event) => {
      // Tab can leave the document for browser chrome without another focusin.
      if (event.key === "Tab") focusedDismissal = null;
    }, true);
    prepareNotifications();
    new MutationObserver(prepareNotifications).observe(document.body, {
      childList: true, subtree: true
    });
  });
})();

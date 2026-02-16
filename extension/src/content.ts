/**
 * OpenMimic Observer — Content Script
 *
 * Injected at `document_idle` on every page (`<all_urls>`).
 *
 * Responsibilities:
 *   1. Log injection (URL, timestamp) for debugging.
 *   2. Notify the background service worker that the script is ready.
 *   3. Listen for commands from the background (e.g. "take a snapshot").
 *   4. Expose hook points that future modules plug into:
 *        - DOM snapshot capture  (dom-capture)
 *        - Click intent tracking (click-capture)
 *        - Dwell / scroll-read   (dwell)
 *        - Secure field detection (secure-field)
 */

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/** A module hook that the content script can register. */
interface ContentModule {
  /** Human-readable name for logging. */
  name: string;
  /** Called once when the content script initialises. */
  init: () => void;
  /** Called when the content script is about to be torn down (navigation). */
  destroy: () => void;
}

/** Messages the background may send to this content script. */
interface BackgroundCommand {
  type: string;
  payload?: Record<string, unknown>;
}

// ---------------------------------------------------------------------------
// Module registry
// ---------------------------------------------------------------------------

const registeredModules: ContentModule[] = [];

/**
 * Register a content-side module.  Modules are initialised in registration
 * order.
 *
 * Future files (dom-capture.ts, click-capture.ts, etc.) will import and
 * call this function during their top-level execution.
 */
export function registerModule(mod: ContentModule): void {
  console.log('[OpenMimic:content] Registering module:', mod.name);
  registeredModules.push(mod);
  mod.init();
}

// ---------------------------------------------------------------------------
// Communication helpers
// ---------------------------------------------------------------------------

/**
 * Send a typed message to the background service worker.
 *
 * Wraps `chrome.runtime.sendMessage` with consistent error handling.
 */
export function sendToBackground(
  type: string,
  payload: Record<string, unknown> = {},
): void {
  chrome.runtime.sendMessage({ type, payload }, (response) => {
    if (chrome.runtime.lastError) {
      // This can happen legitimately if the service worker is restarting.
      console.warn(
        '[OpenMimic:content] sendMessage error:',
        chrome.runtime.lastError.message,
      );
      return;
    }
    if (response && !response.ok) {
      console.warn(
        '[OpenMimic:content] Background rejected message:',
        response.error,
      );
    }
  });
}

// ---------------------------------------------------------------------------
// Background command listener
// ---------------------------------------------------------------------------

chrome.runtime.onMessage.addListener(
  (
    message: BackgroundCommand,
    _sender: chrome.runtime.MessageSender,
    sendResponse: (response: unknown) => void,
  ) => {
    console.log('[OpenMimic:content] Received command:', message.type);

    switch (message.type) {
      case 'request_snapshot':
        // Future: the dom-capture module will handle this.
        console.log('[OpenMimic:content] Snapshot requested (handler not yet registered)');
        sendResponse({ ok: true, note: 'snapshot_not_implemented' });
        break;

      default:
        console.log('[OpenMimic:content] Unknown command:', message.type);
        sendResponse({ ok: false, error: 'unknown_command' });
    }

    return true;
  },
);

// ---------------------------------------------------------------------------
// Teardown
// ---------------------------------------------------------------------------

/**
 * Clean up all registered modules.  Called automatically before the page
 * unloads so modules can remove listeners / observers.
 */
function destroyAllModules(): void {
  for (const mod of registeredModules) {
    try {
      mod.destroy();
      console.log('[OpenMimic:content] Destroyed module:', mod.name);
    } catch (err) {
      console.error('[OpenMimic:content] Error destroying module', mod.name, err);
    }
  }
  registeredModules.length = 0;
}

window.addEventListener('beforeunload', destroyAllModules);

// ---------------------------------------------------------------------------
// Bootstrap
// ---------------------------------------------------------------------------

console.log(
  '[OpenMimic:content] Content script injected at',
  window.location.href,
  'timestamp:',
  new Date().toISOString(),
);

sendToBackground('content_ready', {
  url: window.location.href,
  title: document.title,
  timestamp: new Date().toISOString(),
});

/**
 * OpenMimic Observer — Background Service Worker (MV3)
 *
 * Responsibilities:
 *   1. Log service worker lifecycle events (install, activate).
 *   2. Listen for messages from content scripts and relay them onward.
 *   3. Manage the native messaging connection to the local daemon.
 *
 * This service worker is the single coordination point between the
 * per-tab content scripts and the local daemon process.
 */

import {
  connectNativeHost,
  disconnectNativeHost,
  sendToNative,
  onNativeMessage,
  onNativeDisconnect,
  isConnected,
  type NativeInboundMessage,
} from './native-messaging';

// ---------------------------------------------------------------------------
// Service worker lifecycle
// ---------------------------------------------------------------------------

self.addEventListener('install', () => {
  console.log('[OpenMimic:bg] Service worker installed');
});

self.addEventListener('activate', () => {
  console.log('[OpenMimic:bg] Service worker activated');
  initNativeConnection();
});

// ---------------------------------------------------------------------------
// Native messaging bootstrap
// ---------------------------------------------------------------------------

/**
 * Establish a connection to the daemon.  If the connection drops (e.g. daemon
 * restarts) we schedule a reconnect after a short delay.
 */
function initNativeConnection(): void {
  if (isConnected()) {
    console.log('[OpenMimic:bg] Native connection already active');
    return;
  }

  try {
    connectNativeHost();

    onNativeMessage((message: NativeInboundMessage) => {
      console.log('[OpenMimic:bg] Daemon message:', message.type);
      handleDaemonMessage(message);
    });

    onNativeDisconnect(() => {
      console.warn('[OpenMimic:bg] Lost daemon connection — will reconnect in 5 s');
      setTimeout(initNativeConnection, 5_000);
    });
  } catch (err) {
    console.error('[OpenMimic:bg] Failed to connect to daemon:', err);
    console.log('[OpenMimic:bg] Retrying in 5 s');
    setTimeout(initNativeConnection, 5_000);
  }
}

// ---------------------------------------------------------------------------
// Message handling: content script -> background
// ---------------------------------------------------------------------------

/**
 * Content scripts send messages via `chrome.runtime.sendMessage`.
 * We forward relevant ones to the daemon over the native port.
 */
chrome.runtime.onMessage.addListener(
  (
    message: ContentScriptMessage,
    sender: chrome.runtime.MessageSender,
    sendResponse: (response: BackgroundResponse) => void,
  ) => {
    const tabId = sender.tab?.id ?? -1;
    const url = sender.tab?.url ?? sender.url ?? 'unknown';

    console.log(
      '[OpenMimic:bg] Content script message from tab', tabId,
      'type:', message.type,
      'url:', url,
    );

    switch (message.type) {
      case 'content_ready':
        handleContentReady(tabId, url);
        sendResponse({ ok: true });
        break;

      case 'dom_snapshot':
      case 'click_intent':
      case 'dwell_snapshot':
      case 'scroll_snapshot':
      case 'secure_field_status':
        forwardToDaemon(message, tabId, url);
        sendResponse({ ok: true });
        break;

      default:
        console.warn('[OpenMimic:bg] Unknown message type:', message.type);
        sendResponse({ ok: false, error: 'unknown_message_type' });
    }

    // Return true to keep the message channel open for async sendResponse.
    return true;
  },
);

// ---------------------------------------------------------------------------
// Content script message types
// ---------------------------------------------------------------------------

/** Union of all messages a content script may send to the background. */
interface ContentScriptMessage {
  type:
    | 'content_ready'
    | 'dom_snapshot'
    | 'click_intent'
    | 'dwell_snapshot'
    | 'scroll_snapshot'
    | 'secure_field_status';
  payload?: Record<string, unknown>;
}

/** Standard response back to content scripts. */
interface BackgroundResponse {
  ok: boolean;
  error?: string;
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

function handleContentReady(tabId: number, url: string): void {
  console.log('[OpenMimic:bg] Content script ready in tab', tabId, '—', url);

  if (isConnected()) {
    sendToNative('content_ready', { tabId, url });
  }
}

function forwardToDaemon(
  message: ContentScriptMessage,
  tabId: number,
  url: string,
): void {
  if (!isConnected()) {
    console.warn('[OpenMimic:bg] Daemon not connected — dropping', message.type);
    return;
  }

  sendToNative(message.type, {
    tabId,
    url,
    ...(message.payload ?? {}),
  });
}

/**
 * Handle messages arriving from the daemon.
 *
 * Currently a pass-through logger.  Future modules will route commands
 * (e.g. "request DOM snapshot for tab X") to the appropriate content script.
 */
function handleDaemonMessage(message: NativeInboundMessage): void {
  switch (message.type) {
    case 'ping':
      console.log('[OpenMimic:bg] Daemon ping received');
      sendToNative('pong', {});
      break;

    case 'request_snapshot': {
      const targetTab = message.payload.tabId as number | undefined;
      if (targetTab !== undefined) {
        chrome.tabs.sendMessage(targetTab, {
          type: 'request_snapshot',
          payload: message.payload,
        });
      }
      break;
    }

    default:
      console.log('[OpenMimic:bg] Unhandled daemon message type:', message.type);
  }
}

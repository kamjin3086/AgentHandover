/**
 * Native Messaging client module for OpenMimic Observer.
 *
 * Connects to the local daemon (com.openclaw.apprentice) via Chrome Native
 * Messaging.  The daemon receives browser events (DOM snapshots, click
 * intent, etc.) and pipes back commands or acknowledgements.
 *
 * Message protocol:
 *   Extension -> Daemon:  NativeOutboundMessage
 *   Daemon   -> Extension: NativeInboundMessage
 *
 * Chrome serialises messages as JSON with a 4-byte length prefix on the
 * wire.  The chrome.runtime.connectNative API handles framing automatically.
 */

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const NATIVE_HOST_NAME = 'com.openclaw.apprentice';

// ---------------------------------------------------------------------------
// Message types
// ---------------------------------------------------------------------------

/** Messages sent from the extension to the daemon. */
export interface NativeOutboundMessage {
  /** Discriminator for message routing in the daemon. */
  type: string;
  /** Monotonic sequence number so the daemon can detect dropped messages. */
  seq: number;
  /** ISO-8601 timestamp of when the message was created. */
  timestamp: string;
  /** Arbitrary payload — schema depends on `type`. */
  payload: Record<string, unknown>;
}

/** Messages received from the daemon. */
export interface NativeInboundMessage {
  type: string;
  seq: number;
  timestamp: string;
  payload: Record<string, unknown>;
}

/** Callback for incoming daemon messages. */
export type NativeMessageCallback = (message: NativeInboundMessage) => void;

/** Callback for disconnection events. */
export type NativeDisconnectCallback = () => void;

// ---------------------------------------------------------------------------
// Module state
// ---------------------------------------------------------------------------

let port: chrome.runtime.Port | null = null;
let messageSeq = 0;
const messageListeners: Set<NativeMessageCallback> = new Set();
const disconnectListeners: Set<NativeDisconnectCallback> = new Set();

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

function handleIncomingMessage(message: unknown): void {
  const msg = message as NativeInboundMessage;
  console.log('[OpenMimic:native] Received message from daemon:', msg.type, 'seq:', msg.seq);
  for (const listener of messageListeners) {
    try {
      listener(msg);
    } catch (err) {
      console.error('[OpenMimic:native] Listener threw:', err);
    }
  }
}

function handleDisconnect(): void {
  const lastError = chrome.runtime.lastError;
  if (lastError) {
    console.warn('[OpenMimic:native] Disconnected with error:', lastError.message);
  } else {
    console.log('[OpenMimic:native] Disconnected from daemon');
  }
  port = null;
  for (const listener of disconnectListeners) {
    try {
      listener();
    } catch (err) {
      console.error('[OpenMimic:native] Disconnect listener threw:', err);
    }
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Open a long-lived connection to the native messaging host.
 *
 * If a connection is already open the existing port is returned without
 * creating a second one.  The returned port can be used directly, but
 * prefer `sendToNative()` for type-safe message sending.
 */
export function connectNativeHost(): chrome.runtime.Port {
  if (port !== null) {
    console.log('[OpenMimic:native] Already connected to daemon');
    return port;
  }

  console.log('[OpenMimic:native] Connecting to', NATIVE_HOST_NAME);
  port = chrome.runtime.connectNative(NATIVE_HOST_NAME);

  port.onMessage.addListener(handleIncomingMessage);
  port.onDisconnect.addListener(handleDisconnect);

  console.log('[OpenMimic:native] Connection established');
  return port;
}

/**
 * Close the connection to the native messaging host.
 *
 * Safe to call when already disconnected (no-op).
 */
export function disconnectNativeHost(): void {
  if (port === null) {
    console.log('[OpenMimic:native] Already disconnected');
    return;
  }

  console.log('[OpenMimic:native] Disconnecting from daemon');
  port.disconnect();
  // handleDisconnect fires synchronously on disconnect() and resets `port`.
}

/**
 * Post a typed message to the daemon.
 *
 * A monotonic sequence number and ISO timestamp are attached automatically.
 * Throws if the port is not connected.
 */
export function sendToNative(type: string, payload: Record<string, unknown> = {}): void {
  if (port === null) {
    throw new Error('[OpenMimic:native] Cannot send: not connected to daemon');
  }

  messageSeq += 1;
  const message: NativeOutboundMessage = {
    type,
    seq: messageSeq,
    timestamp: new Date().toISOString(),
    payload,
  };

  console.log('[OpenMimic:native] Sending to daemon:', type, 'seq:', messageSeq);
  port.postMessage(message);
}

/**
 * Register a callback for messages arriving from the daemon.
 *
 * Returns an unsubscribe function.
 */
export function onNativeMessage(callback: NativeMessageCallback): () => void {
  messageListeners.add(callback);
  return () => {
    messageListeners.delete(callback);
  };
}

/**
 * Register a callback for disconnection events.
 *
 * Returns an unsubscribe function.
 */
export function onNativeDisconnect(callback: NativeDisconnectCallback): () => void {
  disconnectListeners.add(callback);
  return () => {
    disconnectListeners.delete(callback);
  };
}

/**
 * Returns true if a native messaging port is currently connected.
 */
export function isConnected(): boolean {
  return port !== null;
}

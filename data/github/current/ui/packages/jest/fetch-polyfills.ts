import {TransformStream} from 'node:stream/web'
import {TextDecoder, TextEncoder} from 'node:util'
import {BroadcastChannel} from 'node:worker_threads'
if (typeof document !== 'undefined') {
  global.TextEncoder ||= TextEncoder
  // @ts-expect-error node and browser api mismatch
  global.TextDecoder ||= TextDecoder
}

// @ts-expect-error node/web types mismatch
global.BroadcastChannel = BroadcastChannel
// @ts-expect-error node/web types mismatch
global.TransformStream = TransformStream

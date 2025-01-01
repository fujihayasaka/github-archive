import util from 'node:util'
import buffer from 'node:buffer'
import stream from 'node:stream'

/**
 * These are copied from https://github.com/github/alloy/blob/main/src/vm.ts
 * If you find you need to update these for the smoke tests to pass, then you will need to update Alloy's
 * vm.ts first and then update this file.
 */

export const allowedSandboxGlobals = {
  require: customRequire,
  console,
  Event,
  URL,
  URLSearchParams,
  EventTarget,
  AbortController,
  setTimeout: () => {},
  setInterval: () => {},
}

function customRequire(module: string) {
  if (module === 'util') return util
  if (module === 'buffer') return buffer
  if (module === 'stream') return stream

  throw new Error(`Cannot find module '${module}'`)
}

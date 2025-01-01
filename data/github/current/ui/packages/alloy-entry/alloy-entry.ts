import {handleRequest} from '@github-ui/react-core/alloy-handler'

/**
 * Welcome to Alloy!
 *
 * If you would like to add SSR to an App/Partial, please add an ssr-entry.ts to your package
 * to automatically register with Alloy. Do not add to this file directly.
 */

const ssrEntries: {[name: string]: () => Promise<unknown> | void} = {
  /* Insert dynamic ssr-entry.ts imports here */
}

// The default export is used to register the named app/partial
// It returns the handleRequest function to be used by Alloy
export default function registerHandler(name: string) {
  if (ssrEntries[name]) {
    ssrEntries[name]() // Register the app/partial
    return handleRequest // Return the handler, which will be able to render the registered app/partial
  }

  throw new Error(`No SSR entry found for ${name}`)
}

// This version of the register function is used with Vite SSR
// Vite uses `import('...')` which requires us to await the result
export async function registerHandlerAsync(name: string) {
  if (ssrEntries[name]) {
    await ssrEntries[name]() // Register the app/partial
    return handleRequest // Return the handler, which will be able to render the registered app/partial
  }

  throw new Error(`No SSR entry found for ${name}`)
}

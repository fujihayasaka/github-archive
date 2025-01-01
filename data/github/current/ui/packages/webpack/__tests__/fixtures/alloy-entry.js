// This fixture simulates the alloy-entry.ts file, which exports a function to register a single handler per reset

const ssrEntries = {
  /* Insert dynamic ssr-entry.ts imports here */
}

/**
 * This function is slightly different from alloy-entry.ts because we don't have the handleRequest function from
 * react-core. Instead, we return the default export from the handler files
 */
export default function registerHandler(name) {
  const handlerEntry = ssrEntries[name]

  if (handlerEntry) {
    return handlerEntry().default
  }

  throw new Error(`Unknown fixture handler name: ${name}`)
}

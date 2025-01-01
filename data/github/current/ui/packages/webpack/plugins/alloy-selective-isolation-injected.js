//  __webpack_modules__ is already defined. This replaces the reset of the webpack setup

;(function () {
  /**
   * This trustedModuleCache persists across self-isolated handlers.
   * It is used to cache modules that are trusted to run without leaks
   * in a shared server-side environment. This is the key piece to "Selective Isolation".
   */
  // eslint-disable-next-line unused-imports/no-unused-vars
  const trustedModuleCache = {}

  /**
   * Keep a list of the initial global context keys.
   * We should NEVER add new global keys, during setup or execution.
   */
  const originalGlobalThisKeys = new Set(Object.keys(globalThis))

  /**
   * When run in a browser (e.g. alloy-profiling), there are a few global keys created
   *  by trusted modules, which we can safely ignore
   */
  if (typeof globalThis.ALLOWED_GLOBAL_KEYS !== 'undefined') {
    for (const key of globalThis.ALLOWED_GLOBAL_KEYS) {
      originalGlobalThisKeys.add(key)
    }
  }

  /**
   * These variables are injected by the webpack plugin at build time.
   */
  // eslint-disable-next-line unused-imports/no-unused-vars
  const safeModuleIds = new Set(/*# safeModuleIds #*/)
  const entryNames = new Set(/*# entryNames #*/)
  const handlers = {}
  const usedHandlers = new Set()

  /**
   * createHandler will create a new self-isolated webpack require function, allowing all untrusted modules to be
   * instantiated in a new cache.
   *
   * This will also call the default export (alloy-entry.ts) with the given name, which will load the related code
   * for that handler, then return the actual handler function.
   */
  function createHandler(name) {
    /**
     * This webpack cache is scoped to a single self-isolated handler. Non-trusted modules will be cached here, then
     * discarded when a new handler is created.
     */
    // eslint-disable-next-line unused-imports/no-unused-vars
    const untrustedModuleCache = {}

    /**
     * Inject the webpack setup here. This includes __webpack_require__ and it's dynamic extensions,
     * as well as the __webpack_exports__ from the original bundle. This may include and IIFE, but ultimately it will
     * create __webpack_exports__ which has the default export we want to return. __webpack_require__ will be modified
     * to use the trustedModuleCache and untrustedModuleCache we've created above.
     */

    /*# webpackSetup #*/

    /**
     * Call the default export with the name of the handler we would like set up. The returned function
     * will be the actual handler that is called by Alloy at render time.
     */
    // eslint-disable-next-line no-undef
    return __webpack_exports__['default'](name)
  }

  /**
   * This is the function that will be called for every render request. The args will contain the name of the handler
   * which will be pulled from the handler cache. We'll mark the handler as "used" after the render, which allows us
   * to recreate used handlers appropriately if the setup function is called again.
   */
  function handleRequest(args) {
    const name = args.name
    usedHandlers.add(name)
    const handler = handlers[name]

    if (!handler) {
      throw new Error(`Requested handler "${name}" was not found. Ensure the ${name} package has an ssr-entry.ts file.`)
    }

    const response = handler(args)
    return response
  }

  function getNewGlobalKeys() {
    return Object.keys(globalThis).filter(key => !originalGlobalThisKeys.has(key))
  }

  /**
   * If this setup function is called again, it means Alloy would like to reset the handlers
   * In this case, we check used handlers, delete them, then recreate them
   */
  function resetHandlers() {
    /**
     * If alloy is running in isolation mode, we expect a reset after every render.
     * Otherwise, we expect only the initial setup to call this function a single time.
     * Any scenario where this is called and more than one handler has been used indicates a bug in Alloy or this plugin.
     */
    if (usedHandlers.size > 1) {
      throw new Error(
        `Expected only one used handler per reset, but found multiple: ${Array.from(usedHandlers).join(', ')}`,
      )
    }

    // Remove the used handlers from the cache, allowing them to be recreated below
    for (const name of usedHandlers) {
      delete handlers[name]
    }
    usedHandlers.clear()

    // Create and cache any missing handlers. One handler on resets, all of them on initial setup.
    for (const name of entryNames) {
      if (!handlers[name]) {
        handlers[name] = createHandler(name)

        // globals can leak between handlers, so we need to ensure none are created, period
        const newGlobalKeys = getNewGlobalKeys()
        if (newGlobalKeys.length) {
          throw new Error(`Unexpected global keys created while creating handler ${name}: ${newGlobalKeys.join(', ')}`)
        }
      }
    }
  }

  /**
   * The setup function is the initial entry point from Alloy. Since we register as a "self-isolating" handler,
   * this function will be called after every render as part of the Alloy "reset" process. For un-isolated
   * workers (e.g. anonymous workers), this function will only be called once. That's ok, because we will cache/keep
   * the handlers for subsequent render requests.
   */
  module.exports = function selfIsolatingSetup() {
    /**
     * Reset all handlers before returning the handler function. On the first call, this will warm _all_ the handlers.
     * On subsequent calls, it will reset any used handlers (should only be one) and then create a new instance (aka a reset).
     */
    resetHandlers()
    return handleRequest
  }
})()

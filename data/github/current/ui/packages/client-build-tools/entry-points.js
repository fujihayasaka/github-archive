// @ts-check
const {parse: parsePath, basename} = require('node:path')
const {globFromRoot, relativePathFromRoot} = require('./path-utils')
const {
  env: {NODE_ENV},
} = require('node:process')

/**
 * We use convention over configuration to determine the entry points for the app. This is done for
 * JS, CSS, and SSR entry points. Keeping the logic for these conventions in this one file makes it easier
 * to share them between build tools, and simpler to update them in the future.
 * The conventions vary, so see the globs in each of the functions below.
 */

/**
 * @param {string[]} entryGlobs
 */
function getEntriesFromGlobs(entryGlobs, fileNameGlob = '*.') {
  /** @type {Record<string, string>} */
  const entries = {}

  for (const entryGlob of entryGlobs || []) {
    const entryPaths = globFromRoot(entryGlob)
    const useFileNameAsName = entryGlob.includes(fileNameGlob)

    for (const path of entryPaths) {
      const {dir, name: fileName} = parsePath(path)
      // Name will be either the file name or the directory name depending on the glob pattern
      const name = useFileNameAsName ? fileName : basename(dir)

      if (entries[name]) {
        throw new Error(`Found duplicate entry: ${name} - ${path} and ${entries[name]}`)
      }

      entries[name] = `./${relativePathFromRoot(path)}`
    }
  }

  return entries
}

/**
 * getJSEntryPoints returns all the JS entry points for the app. These are defined by
 * convention, with most being pulled from ui/packages/*\/entry.ts files.
 */
module.exports.getJSEntryPoints = function getJSEntryPoints() {
  return getEntriesFromGlobs([
    'app/assets/modules/*.ts',
    'app/assets/workers/*.ts',
    ...(NODE_ENV === 'production' ? [] : ['app/assets/preview_modules/*.ts']), // only include preview modules in non-production environments
    'app/assets/modules/react-partials/*/index.ts',
    'ui/packages/*/entry.ts',
    'ui/packages/*/standalone-entry.ts',
  ])
}

/**
 * getStandaloneEntryNames returns the names of the standalone entry points. These
 * entry points are loaded independently in separate environments, such as web workers.
 * They need to contain any base runtime code and ideally live in a single chunk.
 * @param {Record<string, string>} entries
 */
module.exports.getStandaloneEntryNames = function getStandaloneEntryNames(entries) {
  /** @type {Set<string>} */
  const standaloneEntryNames = new Set()

  for (const [name, path] of Object.entries(entries)) {
    if (
      path.endsWith('standalone-entry.ts') ||
      path.includes('app/assets/workers') ||
      path.includes('app/assets/preview_modules')
    ) {
      standaloneEntryNames.add(name)
    }
  }

  return standaloneEntryNames
}

/**
 * getCSSEntryPoints returns all the CSS entry points for the app, which are standalone scss files.
 * Note, this does not include css modules, which are handled by the JS build.
 */
module.exports.getCSSEntryPoints = function getCSSEntryPoints() {
  return getEntriesFromGlobs([
    'app/assets/stylesheets/variables/themes/*.scss',
    'app/assets/stylesheets/marketing/*.scss',
    'app/assets/stylesheets/bundles/*/index.scss',
  ])
}

/**
 * @type {Record<string, string>}
 * These packages do not follow the "package === app name" convention because they are in app/assets/modules
 * All new apps _should_ follow the convention
 */
const appNameOverrides = {
  'blackbird-monolith': 'blackbird-search',
}

/**
 * getSSREntryPoints returns all the SSR entry points, which will be included in the bundle sent to Alloy
 */
module.exports.getSSREntryPoints = function getSSREntryPoints() {
  const entries = getEntriesFromGlobs([
    'ui/packages/*/ssr-entry.ts',
    'app/assets/modules/*/ssr-entry.ts',
    'app/assets/modules/react-partials/*/ssr-entry.ts',
  ])

  // Apply app name overrides
  for (const [name, path] of Object.entries(entries)) {
    const override = appNameOverrides[name]
    if (override) {
      entries[override] = path
      delete entries[name]
    }
  }

  return entries
}

/**
 * getDynamicElementEntryPoints returns all the dynamic catalyst element entry points.
 */
module.exports.getDynamicElementEntryPoints = function getDynamicElementEntryPoints() {
  const entries = getEntriesFromGlobs(
    ['app/components/**/*-element.ts', 'ui/packages/*-element/element-entry.ts'],
    '*-element.', // these files are special in that they always have the `-element` suffix
  )

  // strip the -element suffix from the entry name since the custom element tag names won't include it
  for (const [name, path] of Object.entries(entries)) {
    entries[name.replace('-element', '')] = path
    delete entries[name]
  }
  return entries
}

export type Variants = 'default' | 'pending' | 'failure' | 'success' | 'skipped'

function getFaviconElements() {
  // these will always be present in dev and production environments, not in tests
  return {
    favicon: document.querySelector<HTMLLinkElement>('.js-site-favicon[type="image/svg+xml"]'),
    faviconFallback: document.querySelector<HTMLLinkElement>('.js-site-favicon[type="image/png"]'),
  }
}

/**
 * Update the favicon to the given href.
 * Primarily used by the Rails app to update the favicon via when an element with the data attribute [data-favicon-override]
 * is added or removed from the DOM.
 * See /behaviors/favicon.ts for more information.
 * @param newHref The new href for the favicon.
 */
export function updateFaviconByHref(newHref: string) {
  const {favicon, faviconFallback} = getFaviconElements()
  if (!favicon || !faviconFallback) return

  const colorSchemeSuffix = getColorSchemeSuffix()

  newHref = newHref.substr(0, newHref.lastIndexOf('.'))
  newHref = `${newHref}${colorSchemeSuffix}.svg`
  favicon.href = newHref

  const newFallbackHref = favicon.href.substr(0, favicon.href.lastIndexOf('.'))
  faviconFallback.href = `${newFallbackHref}.png`
}

/**
 * Update the favicon to the current theme. This is used to keep the favicon in sync when the user changes their system theme.
 */
export function syncFaviconToTheme() {
  const {favicon, faviconFallback} = getFaviconElements()
  if (!favicon || !faviconFallback) return

  const colorSchemeSuffix = getColorSchemeSuffix()

  const n = favicon.href.indexOf('-dark.svg')
  const newFaviconName = favicon.href.substr(0, n !== -1 ? n : favicon.href.lastIndexOf('.'))

  favicon.href = `${newFaviconName}${colorSchemeSuffix}.svg`
  faviconFallback.href = `${newFaviconName}${colorSchemeSuffix}.png`
}

/**
 * Update the favicon to the given variant
 * Primarily used by React components to update the favicon when the page status changes.
 * This method abstracts url building logic from the React components.
 */
export function updateFaviconByVariant(variant: Variants) {
  const {favicon, faviconFallback} = getFaviconElements()
  if (!favicon || !faviconFallback) return

  const baseUrl = favicon.getAttribute('data-base-href')
  const variantSuffix = variant === 'default' ? '' : `-${variant}`
  const colorSchemeSuffix = getColorSchemeSuffix()

  if (baseUrl) {
    favicon.href = `${baseUrl}${variantSuffix}${colorSchemeSuffix}.svg`
    faviconFallback.href = `${baseUrl}${variantSuffix}${colorSchemeSuffix}.png`
  }
}

/**
 * Helper method to reset the favicon to the default state.
 */
export function resetFavicon() {
  updateFaviconByVariant('default')
}

function getColorSchemeSuffix() {
  return prefersDarkColorScheme() ? '-dark' : ''
}

function prefersDarkColorScheme() {
  return window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches
}

import {updateFaviconByHref, syncFaviconToTheme, updateFaviconByVariant, resetFavicon} from '../favicon'

describe('favicon', () => {
  let favicon: HTMLLinkElement
  let faviconFallback: HTMLLinkElement

  beforeEach(() => {
    document.body.innerHTML = `
      <link class="js-site-favicon" type="image/svg+xml" href="favicon.svg">
      <link class="js-site-favicon" type="image/png" href="favicon.png">
    `

    // lying to typescript here because we know the elements exist in the test
    favicon = document.querySelector('.js-site-favicon[type="image/svg+xml"]')!
    faviconFallback = document.querySelector('.js-site-favicon[type="image/png"]')!
  })

  afterEach(() => {
    document.body.innerHTML = ''
  })

  describe('light mode', () => {
    beforeEach(() => {
      mockLightMode()
    })

    test('updateFaviconByHref updates the favicon hrefs', () => {
      updateFaviconByHref('/favicons/new-favicon.svg')
      expect(favicon.href).toContain('/favicons/new-favicon.svg')
      expect(faviconFallback.href).toContain('new-favicon.png')
    })

    test('updateFaviconByVariant updates the favicon hrefs based on variant', () => {
      favicon.setAttribute('data-base-href', 'base-favicon')
      updateFaviconByVariant('success')
      expect(favicon.href).toContain('base-favicon-success.svg')
      expect(faviconFallback.href).toContain('base-favicon-success.png')
    })

    test('updateFaviconByVariant resets the favicon to default', () => {
      favicon.setAttribute('data-base-href', 'base-favicon')
      updateFaviconByVariant('pending')

      expect(favicon.href).toContain('base-favicon-pending.svg')
      expect(faviconFallback.href).toContain('base-favicon-pending.png')

      updateFaviconByVariant('default')
      expect(favicon.href).toContain('base-favicon.svg')
      expect(faviconFallback.href).toContain('base-favicon.png')
    })

    test('resetFavicon resets the favicon to default', () => {
      favicon.setAttribute('data-base-href', 'base-favicon')
      updateFaviconByVariant('success')
      resetFavicon()
      expect(favicon.href).toContain('base-favicon.svg')
      expect(faviconFallback.href).toContain('base-favicon.png')
    })
  })

  describe('dark mode', () => {
    beforeEach(() => {
      mockDarkMode()
    })

    test('updateFaviconByHref updates the favicon hrefs', () => {
      updateFaviconByHref('/favicons/new-favicon.svg')
      expect(favicon.href).toContain('/favicons/new-favicon-dark.svg')
      expect(faviconFallback.href).toContain('new-favicon-dark.png')
    })

    test('updateFaviconByVariant updates the favicon hrefs based on variant', () => {
      favicon.setAttribute('data-base-href', 'base-favicon')
      updateFaviconByVariant('success')
      expect(favicon.href).toContain('base-favicon-success-dark.svg')
      expect(faviconFallback.href).toContain('base-favicon-success-dark.png')
    })

    test('updateFaviconByVariant resets the favicon to default', () => {
      favicon.setAttribute('data-base-href', 'base-favicon')
      updateFaviconByVariant('pending')

      expect(favicon.href).toContain('base-favicon-pending-dark.svg')
      expect(faviconFallback.href).toContain('base-favicon-pending-dark.png')

      updateFaviconByVariant('default')
      expect(favicon.href).toContain('base-favicon-dark.svg')
      expect(faviconFallback.href).toContain('base-favicon-dark.png')
    })

    test('resetFavicon resets the favicon to default', () => {
      favicon.setAttribute('data-base-href', 'base-favicon')
      updateFaviconByVariant('success')
      resetFavicon()
      expect(favicon.href).toContain('base-favicon-dark.svg')
      expect(faviconFallback.href).toContain('base-favicon-dark.png')
    })
  })

  describe('theming switching', () => {
    test('syncFaviconToTheme updates the favicon hrefs based on theme', () => {
      mockDarkMode()
      syncFaviconToTheme()

      expect(favicon.href).toContain('favicon-dark.svg')
      expect(faviconFallback.href).toContain('favicon-dark.png')

      mockLightMode()
      syncFaviconToTheme()

      expect(favicon.href).toContain('favicon.svg')
      expect(faviconFallback.href).toContain('favicon.png')
    })
  })
})

function mockDarkMode() {
  Object.defineProperty(window, 'matchMedia', {
    writable: true,
    value: jest.fn().mockImplementation(query => ({
      matches: query === '(prefers-color-scheme: dark)',
      media: query,
      onchange: null,
      addListener: jest.fn(), // Deprecated
      removeListener: jest.fn(), // Deprecated
      addEventListener: jest.fn(),
      removeEventListener: jest.fn(),
      dispatchEvent: jest.fn(),
    })),
  })
}

function mockLightMode() {
  Object.defineProperty(window, 'matchMedia', {
    writable: true,
    value: jest.fn().mockImplementation(query => ({
      matches: query !== '(prefers-color-scheme: dark)',
      media: query,
      onchange: null,
      addListener: jest.fn(), // Deprecated
      removeListener: jest.fn(), // Deprecated
      addEventListener: jest.fn(),
      removeEventListener: jest.fn(),
      dispatchEvent: jest.fn(),
    })),
  })
}

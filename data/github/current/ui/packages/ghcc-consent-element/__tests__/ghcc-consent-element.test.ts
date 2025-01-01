import {GhccConsentElement} from '../ghcc-consent-element'

import {
  initializeConsentControl,
  hasNoCookiePreferences,
  showCookieBanner,
  setConsentToAcceptAll,
} from '@github-ui/cookie-consent'

// Mock the imported cookie-consent functions
jest.mock('@github-ui/cookie-consent', () => ({
  initializeConsentControl: jest.fn(),
  hasNoCookiePreferences: jest.fn(() => false),
  showCookieBanner: jest.fn(),
  setConsentToAcceptAll: jest.fn(),
}))

describe('GhccConsentElement', () => {
  beforeAll(() => {
    if (!customElements.get('ghcc-consent')) {
      customElements.define('ghcc-consent', GhccConsentElement)
    }
  })

  beforeEach(() => {
    jest.clearAllMocks()
  })

  function createGhccConsentElement(attrs: Partial<GhccConsentElement> = {}) {
    const el = document.createElement('ghcc-consent') as GhccConsentElement
    Object.assign(el, attrs)
    document.body.appendChild(el)
    return el
  }

  afterEach(() => {
    document.body.innerHTML = ''
  })

  it('calls initializeConsentControl with the correct locale', async () => {
    const el = createGhccConsentElement({locale: 'pt'})
    await el.connectedCallback()
    expect(initializeConsentControl).toHaveBeenCalledWith('pt')
  })

  it('defaults to en locale if none is provided', async () => {
    const el = createGhccConsentElement()
    await el.connectedCallback()
    expect(initializeConsentControl).toHaveBeenCalledWith('en')
  })

  it('calls setConsentToAcceptAll if consent is not required', async () => {
    ;(hasNoCookiePreferences as jest.Mock).mockReturnValue(true)
    const el = createGhccConsentElement({initialCookieConsentAllowed: 'true', cookieConsentRequired: 'false'})
    await el.connectedCallback()
    expect(setConsentToAcceptAll).toHaveBeenCalled()
    expect(showCookieBanner).not.toHaveBeenCalled()
  })

  it('calls showCookieBanner if consent is required', async () => {
    ;(hasNoCookiePreferences as jest.Mock).mockReturnValue(true)
    const el = createGhccConsentElement({initialCookieConsentAllowed: 'true', cookieConsentRequired: 'true'})
    await el.connectedCallback()
    expect(showCookieBanner).toHaveBeenCalled()
    expect(setConsentToAcceptAll).not.toHaveBeenCalled()
  })

  it('does not set consent if initialCookieConsentAllowed is not true', async () => {
    ;(hasNoCookiePreferences as jest.Mock).mockReturnValue(true)
    const el = createGhccConsentElement({initialCookieConsentAllowed: 'false', cookieConsentRequired: 'true'})
    await el.connectedCallback()
    expect(showCookieBanner).not.toHaveBeenCalled()
    expect(setConsentToAcceptAll).not.toHaveBeenCalled()
  })
})

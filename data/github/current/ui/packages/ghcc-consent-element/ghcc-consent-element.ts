import {controller, attr} from '@github/catalyst'
import {
  initializeConsentControl,
  hasNoCookiePreferences,
  showCookieBanner,
  setConsentToAcceptAll,
} from '@github-ui/cookie-consent'

@controller
export class GhccConsentElement extends HTMLElement {
  @attr declare initialCookieConsentAllowed: string
  @attr declare cookieConsentRequired: string
  @attr declare locale: string

  async connectedCallback() {
    await initializeConsentControl(this.locale || 'en')

    if (this.initialCookieConsentAllowed === 'true' && hasNoCookiePreferences()) {
      this.#setInitialCookieConsent()
    }
  }

  #setInitialCookieConsent() {
    if (this.cookieConsentRequired === 'true') {
      showCookieBanner()
    } else {
      setConsentToAcceptAll()
    }
  }
}

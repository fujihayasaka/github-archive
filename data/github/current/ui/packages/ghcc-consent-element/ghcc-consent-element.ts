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

  async connectedCallback() {
    await initializeConsentControl()

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

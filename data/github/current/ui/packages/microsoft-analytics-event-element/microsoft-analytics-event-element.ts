import {controller, attr} from '@github/catalyst'
import {
  PageActionBehavior,
  type PageActionAccountType,
  type PageActionEventType,
  type PageActionPeriodType,
  type PageActionPropertiesType,
} from '@github-ui/microsoft-analytics'
import {trackPageAction, waitForInitialization} from '@github-ui/microsoft-analytics'

@controller
export class MicrosoftAnalyticsEventElement extends HTMLElement {
  @attr declare behavior: keyof typeof PageActionBehavior
  @attr declare accountType: PageActionAccountType
  @attr declare orderId: string
  @attr declare productTitle: string
  @attr declare periodType: PageActionPeriodType
  @attr declare seats: number

  async connectedCallback() {
    const isInitialized = await waitForInitialization()
    if (isInitialized) {
      this.#sendEvent()
    }
  }

  #sendEvent() {
    const pageActionEvent = {
      behavior: PageActionBehavior[this.behavior],
      name: window.location.pathname,
      uri: window.location.href,
    } as PageActionEventType

    if (['purchase', 'trial'].includes(this.behavior)) {
      pageActionEvent.properties = {
        pageTags: {
          gitHubAccountType: this.accountType,
          orderInfo: {
            id: this.orderId,
            lnItms: [
              {
                title: this.productTitle,
                ...(this.seats && {qty: this.seats}),
                ...(this.periodType && {prdType: this.periodType}),
              },
            ],
          },
          metaTags: {},
        },
      }
    }

    if (this.behavior === 'contact') {
      pageActionEvent.properties = {
        pageTags: {
          mkto_progid: this.productTitle,
          mkto_progname: `${this.productTitle}-ContactSalesForm`,
          mkto_ordid: this.orderId,
        },
      }
    }

    const pageActionProperties = {
      refUri: document.referrer,
    } as PageActionPropertiesType

    trackPageAction(pageActionEvent, pageActionProperties)
  }
}

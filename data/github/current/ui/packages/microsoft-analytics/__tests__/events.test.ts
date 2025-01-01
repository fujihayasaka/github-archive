import {trackBuyIntentEvent, trackContactSalesEvent, trackPurchaseEvent, trackTrialEvent} from '../events'
import {PageActionAccountType, PageActionPeriodType, trackPageAction} from '../microsoft-analytics'

jest.mock('../microsoft-analytics')

describe('tracking events', () => {
  beforeEach(() => {
    jest.clearAllMocks()

    Object.defineProperty(window, 'location', {
      value: {
        pathname: '/path',
        href: 'http://example.com/path',
      },
      writable: true,
    })
    Object.defineProperty(document, 'referrer', {
      value: 'http://example.com/referrer',
      writable: true,
    })
  })

  test('trackContactSalesEvent', async () => {
    const expectedEvent = {
      behavior: 162,
      name: window.location.pathname,
      uri: window.location.href,
      properties: {
        pageTags: {
          mkto_progid: 'exampleTitle',
          mkto_progname: 'exampleTitle-ContactSalesForm',
          mkto_ordid: 'exampleOrderId',
        },
      },
    }
    const expectedProperties = {
      refUri: 'http://example.com/referrer',
    }

    await trackContactSalesEvent({productTitle: 'exampleTitle', orderId: 'exampleOrderId'})

    expect(trackPageAction).toHaveBeenCalledWith(expectedEvent, expectedProperties)
  })

  test('trackPurchaseEvent', async () => {
    const expectedEvent = {
      behavior: 87,
      name: '/path',
      uri: 'http://example.com/path',
      properties: {
        pageTags: {
          gitHubAccountType: PageActionAccountType.New,
          orderInfo: {
            id: 'exampleOrderId',
            lnItms: [
              {
                title: 'exampleTitle',
                qty: 1,
                prdType: PageActionPeriodType.Month,
              },
            ],
          },
        },
      },
    }
    const expectedProperties = {
      refUri: 'http://example.com/referrer',
    }

    await trackPurchaseEvent({
      productTitle: 'exampleTitle',
      orderId: 'exampleOrderId',
      accountType: PageActionAccountType.New,
      seats: 1,
      periodType: PageActionPeriodType.Month,
    })

    expect(trackPageAction).toHaveBeenCalledWith(expectedEvent, expectedProperties)
  })

  test('trackTrialEvent', async () => {
    const expectedEvent = {
      behavior: 200,
      name: '/path',
      uri: 'http://example.com/path',
      properties: {
        pageTags: {
          gitHubAccountType: PageActionAccountType.New,
          orderInfo: {
            id: 'exampleOrderId',
            lnItms: [
              {
                title: 'exampleTitle',
                qty: 1,
                prdType: PageActionPeriodType.Month,
              },
            ],
          },
        },
      },
    }
    const expectedProperties = {
      refUri: 'http://example.com/referrer',
    }

    await trackTrialEvent({
      productTitle: 'exampleTitle',
      orderId: 'exampleOrderId',
      accountType: PageActionAccountType.New,
      seats: 1,
      periodType: PageActionPeriodType.Month,
    })

    expect(trackPageAction).toHaveBeenCalledWith(expectedEvent, expectedProperties)
  })

  test('trackBuyIntentEvent', async () => {
    const expectedEvent = {
      behavior: 20,
      name: '/path',
      uri: 'http://example.com/path',
      properties: {
        pageTags: {
          Content: {
            Id: 'GitHub_CopilotEnablePurchase',
            cN: 'Copilot Business',
          },
        },
      },
    }

    const expectedProperties = {
      refUri: 'http://example.com/referrer',
    }

    await trackBuyIntentEvent({
      id: 'GitHub_CopilotEnablePurchase',
      contentName: 'Copilot Business',
    })

    expect(trackPageAction).toHaveBeenCalledWith(expectedEvent, expectedProperties)
  })
})

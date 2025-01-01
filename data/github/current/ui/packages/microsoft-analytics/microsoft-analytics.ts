import {getPreferencesFromCookie, CONSENT_COOKIE_NAME} from '@github-ui/cookie-consent'
import {gpcDisabled} from '@github-ui/do-not-track'
// Remove this line and replace `withResolvers` with `Promise.withResolvers`
// the day we know no polyfilling is necessary.
import {withResolvers} from '@github-ui/promise-with-resolvers-polyfill'

import Analytics from './ms.analytics-web'

const INSTRUMENTATION_KEY = 'b588e12fde784edfbd5ba42a17219be0-c9e70b20-6770-476b-8e75-5292a6fd04e2-7448'

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const analyticsExports = Analytics as any
export const ApplicationInsights = analyticsExports.ApplicationInsights
const microsoftAnalytics = new ApplicationInsights()

const config = {
  instrumentationKey: INSTRUMENTATION_KEY,
  propertyConfiguration: {
    cookieDomain: 'github.com',
    userConsentCookieName: CONSENT_COOKIE_NAME,
    gpcDataSharingOptIn: gpcDisabled(),
    callback: {
      userConsentDetails: () => getPreferencesFromCookie(),
    },
  },
  webAnalyticsConfiguration: {
    urlCollectHash: true,
    urlCollectQuery: true,
  },
}

const isInitializedPromiseWithResolvers = withResolvers<boolean>()

export function waitForInitialization(): Promise<boolean> {
  return isInitializedPromiseWithResolvers.promise
}

export function initializeAnalytics() {
  microsoftAnalytics.initialize(config, [])
  isInitializedPromiseWithResolvers.resolve(microsoftAnalytics.isInitialized())
}

export type PageActionEventType = {
  behavior: PageActionBehavior
  name: string
  uri: string
  properties: {
    pageTags: PageActionEventTagsType
  }
}

export type PageActionEventTagsType = {
  gitHubAccountType?: string
  orderInfo?: PageActionOrderInfoType
  metaTags?: {
    [name: string]: unknown
  }
  [name: string]: unknown
}

export type PageActionOrderInfoType = {
  id: string
  lnItms: PageActionLineItemType[]
}

export type PageActionLineItemType = {
  title: string
  qty: number
  prdType: PageActionPeriodType
}

export enum PageActionBehavior {
  buyIntent = 20,
  purchase = 87,
  trial = 200,
  contact = 162,
}

export enum PageActionAccountType {
  New = 'new',
  Existing = 'existing',
}

export enum PageActionPeriodType {
  Month = 'month',
  Year = 'year',
  Free = 'free',
}

export type PageActionPropertiesType = {
  refUri: string
}

export async function trackPageAction(
  pageActionEvent: PageActionEventType,
  pageActionProperties: PageActionPropertiesType,
) {
  const isInitialized = await waitForInitialization()
  if (isInitialized) {
    microsoftAnalytics.trackPageAction(pageActionEvent, pageActionProperties)
  }
}

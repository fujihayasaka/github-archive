import type {
  PageActionAccountType,
  PageActionEventType,
  PageActionPeriodType,
  PageActionPropertiesType,
} from './microsoft-analytics'
import {PageActionBehavior, trackPageAction} from './microsoft-analytics'

export async function trackContactSalesEvent({productTitle, orderId}: {productTitle: string; orderId: string}) {
  const pageActionEvent = baseEvent(PageActionBehavior.contact)

  addTag(pageActionEvent, 'mkto_progid', productTitle)
  addTag(pageActionEvent, 'mkto_progname', `${productTitle}-ContactSalesForm`)
  addTag(pageActionEvent, 'mkto_ordid', orderId)

  const pageActionProperties = {refUri: document.referrer}

  return trackPageAction(pageActionEvent, pageActionProperties)
}

export async function trackPurchaseEvent(props: OrderEventProperties) {
  const {pageActionEvent, pageActionProperties} = buildOrderEvent(PageActionBehavior.purchase, props)

  return trackPageAction(pageActionEvent, pageActionProperties)
}

/** Signifies the intent to purchase something in the future */
export async function trackBuyIntentEvent(props: BuyIntentProperties) {
  const {pageActionEvent, pageActionProperties} = buildBuyIntentEvent(PageActionBehavior.buyIntent, props)

  return trackPageAction(pageActionEvent, pageActionProperties)
}

export async function trackTrialEvent(props: OrderEventProperties) {
  const {pageActionEvent, pageActionProperties} = buildOrderEvent(PageActionBehavior.trial, props)

  return trackPageAction(pageActionEvent, pageActionProperties)
}

function buildOrderEvent(
  behavior: PageActionBehavior,
  orderProps: OrderEventProperties,
): {pageActionEvent: PageActionEventType; pageActionProperties: PageActionPropertiesType} {
  const pageActionEvent = baseEvent(behavior)
  addTag(pageActionEvent, 'gitHubAccountType', orderProps.accountType)
  addTag(pageActionEvent, 'orderInfo', {
    id: orderProps.orderId,
    lnItms: [
      {
        title: orderProps.productTitle,
        qty: orderProps.seats,
        prdType: orderProps.periodType,
      },
    ],
  })

  const pageActionProperties = {refUri: document.referrer}

  return {pageActionEvent, pageActionProperties}
}

function buildBuyIntentEvent(behavior: PageActionBehavior, buyIntentProps: BuyIntentProperties) {
  const pageActionEvent = baseEvent(behavior)
  addTag(pageActionEvent, 'Content', {
    Id: buyIntentProps.id,
    cN: buyIntentProps.contentName,
  })

  const pageActionProperties = {refUri: document.referrer}

  return {pageActionEvent, pageActionProperties}
}

function baseEvent(behavior: PageActionBehavior): PageActionEventType {
  return {
    behavior,
    name: window.location.pathname,
    uri: window.location.href,
    properties: {
      pageTags: {},
    },
  }
}

function addTag(event: PageActionEventType, tagName: string, tagValue: unknown) {
  event.properties.pageTags[tagName] = tagValue
}

export type ContactSalesEventProperties = {
  productTitle: string
  orderId: string
}

type OrderEventProperties = {
  productTitle: string
  orderId: string
  accountType: PageActionAccountType
  seats: number
  periodType: PageActionPeriodType
}

type BuyIntentProperties = {
  id: string
  contentName: string
}

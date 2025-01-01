import type {BILLING_MANAGER, OWNER, ENTERPRISE_ORG_OWNER, MEMBER} from '../constants'
import type {BillingTarget, CustomerType} from '../enums'

export type AdminRole = typeof OWNER | typeof BILLING_MANAGER | typeof ENTERPRISE_ORG_OWNER | typeof MEMBER | ''

export interface Customer {
  billingTarget: BillingTarget
  customerId: string
  customerType: CustomerType
  displayId: string
  name: string
  isVNextNative: boolean
  plan: string
  planDuration: string
  seats: number
  pricePerSeat: number
  paymentAmount: number
  hasPendingPlanChange: boolean
}

export interface Enterprise {
  billingTarget?: BillingTarget
  customerId: string
  name: string
  slug: string
}

export interface Item<T> {
  text: string
  id: T
  leadingVisual: () => JSX.Element
  rowLeadingVisual: () => JSX.Element
  viewOnly: boolean
}

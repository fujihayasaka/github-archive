import {BillingTarget, CustomerType} from '../../enums'

import type {Customer} from '../../types/common'

export const GITHUB_INC_CUSTOMER: Customer = {
  billingTarget: BillingTarget.Azure,
  customerId: '1',
  customerType: CustomerType.Business,
  displayId: 'github-inc',
  name: 'GitHub, Inc',
  isVNextNative: true,
  plan: 'enterprise',
  planDuration: 'year',
  seats: 100,
  pricePerSeat: 9,
  paymentAmount: 900,
  hasPendingPlanChange: false,
}

export const ORGANIZATION_CUSTOMER: Customer = {
  billingTarget: BillingTarget.NoBillingTarget,
  customerId: '2',
  customerType: CustomerType.Organization,
  displayId: 'test-org',
  name: 'Test Org',
  isVNextNative: true,
  plan: 'team',
  planDuration: 'year',
  seats: 100,
  pricePerSeat: 9,
  paymentAmount: 900,
  hasPendingPlanChange: false,
}

export const USER_CUSTOMER: Customer = {
  billingTarget: BillingTarget.NoBillingTarget,
  customerId: '3',
  customerType: CustomerType.User,
  displayId: 'test-user',
  name: 'Test User',
  isVNextNative: true,
  plan: 'free',
  planDuration: 'year',
  seats: 0,
  pricePerSeat: 0,
  paymentAmount: 0,
  hasPendingPlanChange: false,
}

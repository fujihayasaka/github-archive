export interface SubscriptionItem {
  price: number
  name: string
  billingCycle: string
  hasPendingDowngrade: boolean
}

export interface CopilotForIndividualsData {
  subscriptionItem?: SubscriptionItem
  onFreeTier: boolean
}

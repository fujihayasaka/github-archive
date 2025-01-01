export interface UpsellData {
  plan: 'enterprise' | 'business' | 'individual'
  overagesVisible: boolean
  overagesEnabled: boolean
  isAdmin: boolean
  bannerDismissed: boolean
  bannerDismissKey: string
  quotaReset: {
    date: string
    dateTime: string
  }
  urls: {
    billing: string
    policy: string
    upsell?: string
  }
}

import type {UpsellData} from '../types'

export const MockUpsellData: UpsellData = {
  plan: 'individual',
  overagesVisible: true,
  overagesEnabled: false,
  isAdmin: false,
  bannerDismissed: false,
  bannerDismissKey: 'foo-bar',
  quotaReset: {
    date: 'Apr 24, 2025',
    dateTime: 'Apr 24, 2025, at 11:30',
  },
  urls: {
    billing: 'foo.com/billing',
    policy: 'foo.com/policy',
    upsell: 'foo.com/upsell',
  },
}

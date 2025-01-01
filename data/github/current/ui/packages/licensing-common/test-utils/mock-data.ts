import type {InvoiceLicenseInfo} from '../types/invoice-license-info'
import type {PendingCycleChange} from '../types/pending-cycle-change'
import type {UsageHintProps} from '../components/UsageHint'

export function getPaymentMethod() {
  return {
    card_type: 'Visa',
    credit_card: true,
    last_four: '1234',
    paypal: false,
  }
}

export function getPendingPlanChange(): PendingCycleChange {
  return {
    changeType: 'change',
    effectiveDate: new Date(2024, 6, 1),
    isCancellation: false,
    isChangingDuration: false,
    isChangingSeats: true,
    newPrice: '$99.99',
    newSeatCount: 5,
    planDisplayName: 'Premium',
    planDuration: 'month',
  }
}

export function getInvoiceLicenseInfo(): InvoiceLicenseInfo {
  return {
    actionType: 'upgrade',
    expired: false,
    hasFutureRenewal: false,
    isGHASRenewal: false,
    isGHERenewal: true,
    statusMessage: {
      text: 'Your Enterprise Cloud upgrade is being processed.',
      variant: 'success',
    },
  }
}

export const skus = [
  {
    sku: 'business',
    unitPrice: 19,
    consumedLicenses: 3,
  },
  {
    sku: 'enterprise',
    unitPrice: 39,
    consumedLicenses: 5,
  },
]

export function getCopilotPaymentSummaryProps() {
  return {
    billingTermEndDate: 'January 20, 2025',
    totalCost: 252,
    skus,
  }
}

export function getSearchBarProps() {
  return {
    searchQuery: '',
    setSearchQuery: (_query: string) => {
      _query = _query.toLowerCase() // Mock implementation for updating the search query
    },
    placeholder: 'Search or filter organizations',
    ariaLabel: 'Search or filter organizations',
  }
}

export function getSkus() {
  return skus
}

export function getUsageHintProps(): UsageHintProps {
  return {
    title: 'Consumed licenses',
    description:
      'Active committers who contributed to at least one private organization-owned or user-owned repository.',
    learnMoreUrl: 'https://docs.github.com/en/billing',
    label: 'About consumed licenses',
  }
}

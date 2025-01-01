import type {LicensingAdvancedSecurityOverviewProps} from '../components/LicensingAdvancedSecurityOverview'
import type {
  LicensingAdvancedSecuritySummaryProps,
  SelfServeSubscriptionInfo,
} from '../components/LicensingAdvancedSecuritySummary'
import type {LicenseUsageSummaryHeaderProps} from '../components/LicenseUsageSummaryHeader'
import type {LicenseUsageHintProps} from '../components/LicenseUsageHint'
import type {PaymentSummaryProps} from '../components/PaymentSummary'
import type {LicenseUsageProgressBarProps} from '../components/LicenseUsageProgressBar'
import type {LicenseUsageSummaryItemProps} from '../components/LicenseUsageSummaryItem'
import type {PendingCycleChange} from '@github-ui/licensing-common/types/pending-cycle-change'

export const skus = [
  {
    availableLicenses: 7,
    consumedLicenses: 3,
    name: 'Secret Protection and Code Security licenses',
    purchasedLicenses: 10,
    sku: 'bundled',
    unitPrice: 49,
    billableLicenses: 3,
    billableAmount: 147,
  },
]
const ghasProps = {
  billingCycle: 'Monthly',
  billableLicenses: 5,
  billingTermEndDate: '2025-02-27T00:00:00.000',
  currentPayment: '$100.00',
  isAdvancedSecurityEnabled: true,
  isBundled: true,
  isManagingSeats: false,
  isMeteredLicensed: true,
  isSelfServeAdvancedSecurity: false,
  paymentMethod: getPaymentMethod(),
  selfServeSubscriptionInfo: undefined,
  totalPurchasedLicenses: 10,
  skus,
  unlimitedLicense: false,
}

const usageHeaderProps = {
  title: 'Consumed licenses',
  description: 'Active committers who contributed to at least one private organization-owned or user-owned repository.',
}

export function getLicensingAdvancedSecurityOverviewProps(): LicensingAdvancedSecurityOverviewProps {
  return {
    enterpriseContactUrl: '',
    isStafftools: false,
    slug: 'avocado',
    ghas: ghasProps,
  }
}

export function getLicensingAdvancedSecuritySummaryProps(): LicensingAdvancedSecuritySummaryProps {
  return ghasProps
}

export function getLicenseUsageSummaryHeaderProps(): LicenseUsageSummaryHeaderProps {
  return usageHeaderProps
}

export function getLicenseUsageHintProps(): LicenseUsageHintProps {
  return usageHeaderProps
}

export function getPaymentMethod() {
  return {
    card_type: 'Visa',
    credit_card: true,
    last_four: '1234',
    paypal: false,
  }
}

export function getPaymentSummaryProps(): PaymentSummaryProps {
  return {
    billingCycle: 'Monthly',
    billableLicenses: 5,
    isBundled: true,
    isMeteredLicensed: true,
    billingTermEndDate: '2025-02-27T00:00:00.000',
    currentPayment: '$100.00',
    skus,
  }
}

export function getLicenseUsageProgressBarProps(): LicenseUsageProgressBarProps {
  return {
    consumedLicenses: 5,
    purchasedLicenses: 19,
  }
}

export function getLicenseUsageSummaryItemProps(): LicenseUsageSummaryItemProps {
  return {
    consumedLicenses: 5,
    description: 'Secret Protection and Code Security licenses',
    isVolumeLicensed: false,
    purchasedLicenses: 19,
    unlimitedLicense: false,
  }
}

export function getPendingPlanChange(): PendingCycleChange {
  return {
    changeType: 'change',
    effectiveDate: new Date(2024, 6, 1),
    id: 100,
    isCancellation: false,
    isChangingDuration: false,
    isChangingSeats: true,
    newPrice: '$99.99',
    newSeatCount: 5,
    planDisplayName: 'GitHub Advanced Security',
    planDuration: 'month',
  }
}

export function getSelfServeSubscriptionInfo(): SelfServeSubscriptionInfo {
  return {
    expiration: '2025-03-21T00:00:00.000',
    pendingCycleChange: getPendingPlanChange(),
  }
}

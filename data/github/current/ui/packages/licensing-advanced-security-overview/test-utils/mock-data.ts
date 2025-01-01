import type {LicensingAdvancedSecurityOverviewProps} from '../components/LicensingAdvancedSecurityOverview'
import type {
  LicensingAdvancedSecuritySummaryProps,
  SelfServeSubscriptionInfo,
} from '../components/LicensingAdvancedSecuritySummary'
import type {LicenseUsageProgressBarProps} from '../components/LicenseUsageProgressBar'
import type {LicenseUsageSummaryItemProps} from '../components/LicenseUsageSummaryItem'
import type {PendingCycleChange} from '@github-ui/licensing-common/types/pending-cycle-change'
import type {CSVDownloaderProps} from '../components/CSVDownloader'
import type {ServerLicensesFooterProps} from '../components/ServerLicensesFooter'
import type {Sku} from '../types/sku'
import type {InvoiceLicenseInfo} from '@github-ui/licensing-common/types/invoice-license-info'

export const skus: Sku[] = [
  {
    consumedLicenses: 3,
    name: 'Advanced Security',
    purchasedLicenses: 10,
    sku: 'bundled',
    unitPrice: 49,
    billableLicenses: 3,
    billableAmount: 147,
    serverOnlyConsumedLicenses: 0,
    unlimitedLicense: false,
  },
  {
    consumedLicenses: 2,
    name: 'Code Security',
    purchasedLicenses: 7,
    sku: 'code-security',
    unitPrice: 30,
    billableLicenses: 2,
    billableAmount: 60,
    serverOnlyConsumedLicenses: 0,
    unlimitedLicense: false,
  },
  {
    consumedLicenses: 1,
    name: 'Secret Protection',
    purchasedLicenses: 4,
    sku: 'secret-protection',
    unitPrice: 19,
    billableLicenses: 1,
    billableAmount: 19,
    serverOnlyConsumedLicenses: 0,
    unlimitedLicense: false,
  },
]

const ghasProps = {
  billingCycle: 'Monthly',
  billableLicenses: 5,
  billingTermEndDate: '2025-02-27T00:00:00.000',
  buyButtonPath: '',
  configureButtonPath: '',
  currentPayment: '$100.00',
  eligibleForTrial: false,
  isAdvancedSecurityEnabled: true,
  ghasFeaturesUrl: '',
  isBundled: true,
  isManagingSeats: false,
  isMeteredLicensed: true,
  isSelfServeAdvancedSecurity: false,
  paymentMethod: getPaymentMethod(),
  selfServeSubscriptionInfo: undefined,
  selfServeTrialInfo: undefined,
  tradeScreeningResult: undefined,
  totalPurchasedLicenses: 10,
  skus,
  unlimitedLicense: false,
  usageExceededMessage: undefined,
  usageAtCapacityMessage: undefined,
}

export function getLicensingAdvancedSecurityOverviewProps(): LicensingAdvancedSecurityOverviewProps {
  return {
    enterpriseContactUrl: '',
    isStafftools: false,
    slug: 'avocado',
    ghas: ghasProps,
    isTeams: false,
    tradeScreeningResult: getTradeScreeningResult(),
  }
}

export function getLicensingAdvancedSecuritySummaryProps(): LicensingAdvancedSecuritySummaryProps {
  return ghasProps
}

export function getPaymentMethod() {
  return {
    card_type: 'Visa',
    credit_card: true,
    last_four: '1234',
    paypal: false,
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

export function getCSVDownloaderProps(): CSVDownloaderProps {
  return {skus}
}

export function getTradeScreeningResult() {
  return {
    isTradeRestricted: false,
    className: '',
    description: '',
    title: '',
  }
}

export function getSelfServeTrialInfo() {
  return {
    organizationToOnboard: 'test-org',
    showNoOrgsWarning: false,
    trialDays: 30,
    trialExpired: false,
  }
}

export function getServerLicensesFooterProps(): ServerLicensesFooterProps {
  return {
    licensesInfo: {
      prefix: 'Additional users from GitHub Connect: ',
      count: 5,
      suffix: ' for Advanced Security',
    },
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

export function getTrialInfo() {
  return {
    expirationDate: new Date('2024-05-31T00:00:00.000-07:00'),
    isActive: true,
    trialLicensesAllowed: 50,
  }
}

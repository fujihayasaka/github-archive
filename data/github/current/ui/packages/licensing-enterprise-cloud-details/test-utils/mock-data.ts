import type {EnterpriseCloudDetailsProps} from '../EnterpriseCloudDetails'

export function getLicensingEnterpriseCloudDetailsProps(): EnterpriseCloudDetailsProps {
  return {
    billingTermEndDate: '2024-06-30',
    canViewMembers: true,
    currentPayment: '$0.00',
    enterpriseContactUrl: 'https://enterprise.github.com/contact',
    enterpriseLicensesBillable: 10,
    enterpriseLicensesConsumed: 8,
    enterpriseLicensesPurchased: 10,
    isMonthly: true,
    isVolumeLicensed: false,
    isVssEnabled: false,
    slug: 'test-enterprise-cloud',
    trialInfo: undefined,
    unitCost: '$10.00',
    vssLicensesConsumed: 0,
    vssLicensesPurchasedWithOverage: 0,
  }
}

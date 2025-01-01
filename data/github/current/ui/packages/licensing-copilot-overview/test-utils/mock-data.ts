import type {SummaryProps} from '../components/Summary'

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

const copilotProps = {
  isCopilotEnabled: true,
  businessSlug: 'business-slug',
  copilotTocLink: 'https://www.example.com',
  cfbHelpLink: 'https://www.example.com',
  cfeHelpLink: 'https://www.example.com',
  skus,
  billingTermEndDate: 'January, 20 2025',
  totalCost: 252,
}

export function getSummaryProps(): SummaryProps {
  return copilotProps
}

export function getOverviewProps() {
  return {
    enterpriseContactUrl: '',
    isStafftools: false,
    slug: 'avocado',
    copilot: copilotProps,
  }
}

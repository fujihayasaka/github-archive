import type {CopilotDetailsProps} from '../CopilotDetails'

export function getCopilotDetailsProps(): CopilotDetailsProps {
  return {
    copilot: copilotProps,
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

const copilotProps = {
  skus,
  billingTermEndDate: 'January, 20 2025',
  totalCost: 252,
}

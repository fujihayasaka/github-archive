import type {Meta, StoryObj} from '@storybook/react'
import {CopilotPaymentSummary} from './CopilotPaymentSummary'
import {getSkus} from '../test-utils/mock-data'

const meta = {
  title: 'Apps/LicensingCommon/CopilotPaymentSummary',
  component: CopilotPaymentSummary,
  args: {
    billingTermEndDate: 'January 20, 2025',
    totalCost: 252,
    skus: getSkus(),
  },
} satisfies Meta<typeof CopilotPaymentSummary>

export default meta

type Story = StoryObj<typeof CopilotPaymentSummary>

export const Default: Story = {}

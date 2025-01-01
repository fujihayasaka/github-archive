import type {Meta, StoryObj} from '@storybook/react'
import {PaymentSummary} from './PaymentSummary'

const meta = {
  title: 'Apps/Licensing/Common/PaymentSummary',
  component: PaymentSummary,
  args: {
    title: 'Monthly payment',
    currentPayment: '$20,000.00',
    description: 'Amount based on 1,000 billable licenses, due by January 1, 2025.',
  },
} satisfies Meta<typeof PaymentSummary>

export default meta

type Story = StoryObj<typeof PaymentSummary>

export const Default: Story = {}

export const WithMoreDetails: Story = {
  args: {
    moreDetailsBody: (
      <div>
        <p>More details about the payment summary.</p>
        <p>This is a second paragraph.</p>
        <p>This is a third paragraph.</p>
        <p>This is a fourth paragraph.</p>
      </div>
    ),
  },
}

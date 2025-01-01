import type {Meta, StoryObj} from '@storybook/react'
import {NavigationContextProvider} from '../contexts/NavigationContext'
import {Product} from '../types/product'
import {InvoiceRenewalButton} from './InvoiceRenewalButton'

const meta = {
  title: 'Apps/Licensing/Common/InvoiceRenewalButton',
  component: InvoiceRenewalButton,
  args: {
    invoiceLicenseInfo: {
      actionType: 'upgrade',
      expired: false,
      hasFutureRenewal: false,
      isGHASRenewal: false,
      isGHERenewal: false,
    },
    product: Product.GHEC,
  },
  decorators: [
    Story => (
      <NavigationContextProvider enterpriseContactUrl="" isTeams={false} isStafftools={false} slug={'test-slug'}>
        <Story />
      </NavigationContextProvider>
    ),
  ],
} satisfies Meta<typeof InvoiceRenewalButton>

export default meta

type Story = StoryObj<typeof InvoiceRenewalButton>

export const Default: Story = {}

export const ContactSales: Story = {
  args: {
    invoiceLicenseInfo: {
      expired: false,
      hasFutureRenewal: false,
      statusMessage: {
        text: 'Your upgrade failed, please contact sales',
        variant: 'critical',
      },
    },
  },
}

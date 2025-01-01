import type {Meta, StoryObj} from '@storybook/react'
import {InvoiceRenewalLabel} from './InvoiceRenewalLabel'

const meta = {
  title: 'Apps/LicensingCommon/InvoiceRenewalLabel',
  component: InvoiceRenewalLabel,
  args: {
    invoiceLicenseInfo: {
      actionType: 'renewal',
      expired: false,
      hasFutureRenewal: true,
      isGHASRenewal: false,
      isGHERenewal: false,
      renewalScheduledStartDate: '2024-04-01T:00:00:00.000Z',
    },
  },
} satisfies Meta<typeof InvoiceRenewalLabel>

export default meta

type Story = StoryObj<typeof InvoiceRenewalLabel>

export const Default: Story = {}

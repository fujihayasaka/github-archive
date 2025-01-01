import type {Meta, StoryObj} from '@storybook/react'
import {LicensingAdvancedSecuritySummary} from './LicensingAdvancedSecuritySummary'
import {
  getLicensingAdvancedSecuritySummaryProps,
  getSelfServeSubscriptionInfo,
  getInvoiceLicenseInfo,
  getTrialInfo,
  skus,
} from '../test-utils/mock-data'

const meta = {
  title: 'Apps/Licensing/Advanced Security/LicensingAdvancedSecuritySummary',
  component: LicensingAdvancedSecuritySummary,
  args: getLicensingAdvancedSecuritySummaryProps(),
} satisfies Meta<typeof LicensingAdvancedSecuritySummary>

export default meta

type Story = StoryObj<typeof LicensingAdvancedSecuritySummary>

export const Default: Story = {
  name: 'Default',
  render: args => <LicensingAdvancedSecuritySummary {...args} />,
}

export const ManageSeats: Story = {
  parameters: {
    a11y: {
      test: 'todo',
    },
  },
  args: {
    isManagingSeats: true,
  },

  name: 'Manage Seats',
  render: args => <LicensingAdvancedSecuritySummary {...args} />,
}

export const PendingPlanChange: Story = {
  args: {
    selfServeSubscriptionInfo: getSelfServeSubscriptionInfo(),
  },
  name: 'Pending Plan Change',
  render: args => <LicensingAdvancedSecuritySummary {...args} />,
}

export const InvoiceLicenseInfo: Story = {
  args: {
    invoiceLicenseInfo: getInvoiceLicenseInfo(),
  },
  name: 'Invoice License Info',
  render: args => <LicensingAdvancedSecuritySummary {...args} />,
}

export const TrialInfo: Story = {
  args: {
    trialInfo: getTrialInfo(),
  },
  name: 'Trial Info',
  render: args => <LicensingAdvancedSecuritySummary {...args} />,
}

export const ServerOnlyLicenses: Story = {
  args: {
    isMeteredLicensed: false,
    isBundled: false,
    skus: skus.map((sku, index) => (index !== 0 ? {...sku, serverOnlyConsumedLicenses: 2} : sku)),
  },
  name: 'Server Only Licenses',
  render: args => <LicensingAdvancedSecuritySummary {...args} />,
}

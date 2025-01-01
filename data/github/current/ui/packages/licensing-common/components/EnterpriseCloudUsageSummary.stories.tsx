import type {Meta, StoryObj} from '@storybook/react'
import {EnterpriseCloudUsageSummary} from './EnterpriseCloudUsageSummary'

const meta = {
  title: 'Apps/Licensing/Common/EnterpriseCloudUsageSummary',
  component: EnterpriseCloudUsageSummary,
  args: {
    canViewMembers: true,
    isTrial: false,
    isVolumeLicensed: false,
    isVssEnabled: false,
    enterpriseLicensesConsumed: 0,
    enterpriseLicensesPurchased: 0,
    vssLicensesConsumed: 0,
    vssLicensesPurchasedWithOverage: 0,
  },
} satisfies Meta<typeof EnterpriseCloudUsageSummary>

export default meta

type Story = StoryObj<typeof EnterpriseCloudUsageSummary>

export const Metered: Story = {
  name: 'Metered-licensed',
  args: {
    isVolumeLicensed: false,
    enterpriseLicensesConsumed: 123,
    enterpriseLicensesPurchased: 567,
    vssLicensesConsumed: 0,
    vssLicensesPurchasedWithOverage: 0,
  },
}

export const MeteredTrial: Story = {
  name: 'Metered-licensed, trial',
  args: {
    isTrial: true,
    isVolumeLicensed: false,
    enterpriseLicensesConsumed: 123,
    enterpriseLicensesPurchased: 567,
    vssLicensesConsumed: 0,
    vssLicensesPurchasedWithOverage: 0,
  },
}

// Note: Metered + VSS coming soon

export const VolumeLicensed: Story = {
  name: 'Volume-licensed',
  args: {
    isVolumeLicensed: true,
    enterpriseLicensesConsumed: 123,
    enterpriseLicensesPurchased: 567,
    vssLicensesConsumed: 0,
    vssLicensesPurchasedWithOverage: 0,
  },
}

export const VolumeLicensedTrial: Story = {
  name: 'Volume-licensed, trial',
  args: {
    isTrial: true,
    isVolumeLicensed: true,
    enterpriseLicensesConsumed: 123,
    enterpriseLicensesPurchased: 567,
    vssLicensesConsumed: 0,
    vssLicensesPurchasedWithOverage: 0,
  },
}

export const VolumeLicensedVSS: Story = {
  name: 'Volume-licensed, VSS bundle',
  args: {
    isVolumeLicensed: true,
    enterpriseLicensesConsumed: 17,
    enterpriseLicensesPurchased: 100,
    vssLicensesConsumed: 6,
    vssLicensesPurchasedWithOverage: 20,
  },
}

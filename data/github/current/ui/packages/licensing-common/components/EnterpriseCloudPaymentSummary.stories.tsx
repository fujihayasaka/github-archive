import type {Meta, StoryObj} from '@storybook/react'
import {EnterpriseCloudPaymentSummary} from './EnterpriseCloudPaymentSummary'

const meta = {
  title: 'Apps/Licensing/Common/EnterpriseCloudPaymentSummary',
  component: EnterpriseCloudPaymentSummary,
  args: {
    billingTermEndDate: '2021-12-26',
    currentPayment: '$123.45',
    enterpriseLicensesBillable: 10,
    isMonthly: false,
    isTrial: false,
    isVolumeLicensed: false,
    unitCost: '$12.34',
  },
} satisfies Meta<typeof EnterpriseCloudPaymentSummary>

export default meta

type Story = StoryObj<typeof EnterpriseCloudPaymentSummary>

export const Metered: Story = {
  name: 'Metered-licensed',
  args: {
    isVolumeLicensed: false,
    enterpriseLicensesBillable: 123,
  },
}

export const MeteredTrial: Story = {
  name: 'Metered-licensed, trial',
  args: {
    isMonthly: true,
    isTrial: true,
    isVolumeLicensed: false,
    enterpriseLicensesBillable: 123,
  },
}

export const Volume: Story = {
  name: 'Volume-licensed',
  args: {
    isVolumeLicensed: true,
    enterpriseLicensesBillable: 123,
  },
}

export const VolumeTrial: Story = {
  name: 'Volume-licensed, trial',
  args: {
    isMonthly: true,
    isTrial: true,
    isVolumeLicensed: true,
    enterpriseLicensesBillable: 123,
  },
}

export const VolumeVss: Story = {
  name: 'Volume-licensed, VSS',
  args: {
    isVssEnabled: true,
    isVolumeLicensed: true,
    enterpriseLicensesBillable: 123,
  },
}

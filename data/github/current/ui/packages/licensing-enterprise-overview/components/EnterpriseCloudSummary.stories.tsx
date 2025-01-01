import type {Meta, StoryObj} from '@storybook/react'
import {EnterpriseCloudSummary} from './EnterpriseCloudSummary'
import {getEnterpriseCloudSummaryProps, getPendingPlanChange} from '../test-utils/mock-data'

const meta = {
  title: 'Apps/Licensing/Enterprise Cloud/EnterpriseCloudSummary',
  component: EnterpriseCloudSummary,
  args: getEnterpriseCloudSummaryProps(),
} satisfies Meta<typeof EnterpriseCloudSummary>

export default meta

type Story = StoryObj<typeof EnterpriseCloudSummary>

export const Default: Story = {
  name: 'Default',
  render: args => <EnterpriseCloudSummary {...args} />,
}

export const ManagingSeats: Story = {
  parameters: {
    a11y: {
      test: 'todo',
    },
  },
  name: 'Managing Seats',
  args: {
    isManagingSeats: true,
  },
  render: args => <EnterpriseCloudSummary {...args} />,
}

export const PendingPlanChange: Story = {
  name: 'Pending Plan Change',
  args: {
    pendingCycleChange: getPendingPlanChange(),
  },
  render: args => <EnterpriseCloudSummary {...args} />,
}

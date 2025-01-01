import type {Meta, StoryObj} from '@storybook/react'
import type {ClosedSecurityCampaignsListItemsProps} from '../ClosedSecurityCampaignsListItems'
import {ClosedSecurityCampaignsListItems} from '../ClosedSecurityCampaignsListItems'
import {getSecurityCampaignWithCounts} from '@github-ui/security-campaigns-shared/test-utils/mock-data'
import {QueryClientProvider} from '@tanstack/react-query'
import {getQueryClient} from '@github-ui/security-campaigns-shared/utils/query-client'
import {ListView} from '@github-ui/list-view'

const meta = {
  title: 'Apps/Security Campaigns/ClosedSecurityCampaignsListItems',
  component: ClosedSecurityCampaignsListItems,
  decorators: [
    Story => (
      <ListView title="Closed campaigns" titleHeaderTag="h3">
        <QueryClientProvider client={getQueryClient()}>
          <Story />
        </QueryClientProvider>
      </ListView>
    ),
  ],
} satisfies Meta<typeof ClosedSecurityCampaignsListItems>

export default meta
type Story = StoryObj<typeof ClosedSecurityCampaignsListItems>

const endsAtDateInPast = new Date(Date.now() - 1000 * 60 * 60 * 24 * 7)
const closedAtDateInPast = new Date(Date.now() - 1000 * 60 * 60)

const defaultArgs: ClosedSecurityCampaignsListItemsProps = {
  campaigns: [],
  isPending: false,
  isError: false,
  onMutationError: () => undefined,
}

export const Pending: Story = {
  name: 'Pending',
  render: (args: ClosedSecurityCampaignsListItemsProps) => <ClosedSecurityCampaignsListItems {...args} />,
  args: {
    ...defaultArgs,
    isPending: true,
  },
}

export const Empty: Story = {
  name: 'Empty',
  render: (args: ClosedSecurityCampaignsListItemsProps) => <ClosedSecurityCampaignsListItems {...args} />,
  args: {
    ...defaultArgs,
  },
}

export const MultipleCampaigns: Story = {
  name: 'Multiple Campaigns',
  render: (args: ClosedSecurityCampaignsListItemsProps) => <ClosedSecurityCampaignsListItems {...args} />,
  args: {
    ...defaultArgs,
    campaigns: [
      {
        ...getSecurityCampaignWithCounts(),
        id: 1,
        number: 1,
        endsAt: endsAtDateInPast.toISOString(),
        closedAt: closedAtDateInPast.toISOString(),
        openCount: 0,
        closedCount: 90,
      },
      {
        ...getSecurityCampaignWithCounts(),
        id: 2,
        number: 2,
        endsAt: endsAtDateInPast.toISOString(),
        closedAt: closedAtDateInPast.toISOString(),
        openCount: 14,
        closedCount: 90,
      },
    ],
  },
}

export const Error: Story = {
  name: 'Error',
  render: (args: ClosedSecurityCampaignsListItemsProps) => <ClosedSecurityCampaignsListItems {...args} />,
  args: {
    ...defaultArgs,
    isError: true,
  },
}

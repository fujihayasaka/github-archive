import type {Meta, StoryObj} from '@storybook/react'
import type {SecurityCampaignsListItemsProps} from '../SecurityCampaignsListItems'
import {SecurityCampaignsListItems} from '../SecurityCampaignsListItems'
import {ListView} from '@github-ui/list-view'
import {MemoryRouter} from 'react-router-dom'
import {BannerProvider} from '@github-ui/role-assignments/banner-provider'
import {getSecurityCampaignWithCounts} from '../../test-utils/mock-data'

const meta = {
  title: 'Apps/Security Campaigns/SecurityCampaignsListItems',
  component: SecurityCampaignsListItems,
  decorators: [
    Story => (
      <MemoryRouter>
        <BannerProvider>
          <ListView title="Closed campaigns" titleHeaderTag="h3">
            <Story />
          </ListView>
        </BannerProvider>
      </MemoryRouter>
    ),
  ],
} satisfies Meta<typeof SecurityCampaignsListItems>

export default meta
type Story = StoryObj<typeof SecurityCampaignsListItems>

const endsAtDateInPast = new Date(Date.now() - 1000 * 60 * 60 * 24 * 7)
const closedAtDateInPast = new Date(Date.now() - 1000 * 60 * 60)

const defaultArgs: SecurityCampaignsListItemsProps = {
  organizationLogin: 'github',
  campaigns: [],
  campaignState: 'closed',
  openCampaignsCount: 0,
  maxOpenCampaigns: 10,
  hasOpenSpam: false,
  allowActions: true,
  isPending: false,
  isError: false,
  onMutationError: () => undefined,
}

export const Pending: Story = {
  name: 'Pending',
  render: (args: SecurityCampaignsListItemsProps) => <SecurityCampaignsListItems {...args} />,
  args: {
    ...defaultArgs,
    isPending: true,
  },
}

export const Empty: Story = {
  name: 'Empty',
  render: (args: SecurityCampaignsListItemsProps) => <SecurityCampaignsListItems {...args} />,
  args: {
    ...defaultArgs,
  },
}

export const MultipleCampaigns: Story = {
  name: 'Multiple Closed Campaigns',
  render: (args: SecurityCampaignsListItemsProps) => <SecurityCampaignsListItems {...args} />,
  args: {
    ...defaultArgs,
    showLeadingIcon: true,
    showManagers: true,
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

export const MultipleOpenCampaigns: Story = {
  name: 'Multiple Open Campaigns',
  render: (args: SecurityCampaignsListItemsProps) => <SecurityCampaignsListItems {...args} />,
  args: {
    ...defaultArgs,
    showLeadingIcon: true,
    showManagers: true,
    campaigns: [
      {
        ...getSecurityCampaignWithCounts(),
        id: 1,
        number: 1,
        endsAt: endsAtDateInPast.toISOString(),
        openCount: 0,
        closedCount: 90,
      },
      {
        ...getSecurityCampaignWithCounts(),
        id: 2,
        number: 2,
        endsAt: endsAtDateInPast.toISOString(),
        openCount: 14,
        closedCount: 90,
      },
    ],
  },
}

export const Error: Story = {
  name: 'Error',
  render: (args: SecurityCampaignsListItemsProps) => <SecurityCampaignsListItems {...args} />,
  args: {
    ...defaultArgs,
    isError: true,
  },
}

export const DraftCampaigns: Story = {
  name: 'Draft Campaigns',
  render: (args: SecurityCampaignsListItemsProps) => <SecurityCampaignsListItems {...args} />,
  args: {
    ...defaultArgs,
    showLeadingIcon: true,
    showManagers: true,
    campaigns: [
      {
        ...getSecurityCampaignWithCounts(),
        id: 1,
        number: 1,
        publishedAt: null,
      },
      {
        ...getSecurityCampaignWithCounts(),
        id: 2,
        number: 2,
        publishedAt: null,
      },
    ],
  },
}

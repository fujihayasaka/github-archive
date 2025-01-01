import type {Meta} from '@storybook/react'
import {CampaignProgressBar, type CampaignProgressBarProps} from '../CampaignProgressBar'

const meta = {
  title: 'Apps/Security Campaigns/Campaign progress bar',
  component: CampaignProgressBar,
} satisfies Meta<typeof CampaignProgressBar>

export default meta

export const WithNoClosedAlerts = {
  args: {
    openCount: 10,
    closedCount: 0,
    openWithLinksCount: 0,
  },
  render: (args: CampaignProgressBarProps) => <CampaignProgressBar {...args} />,
}

export const WithClosedAlerts = {
  args: {
    openCount: 4,
    closedCount: 6,
  },
  render: (args: CampaignProgressBarProps) => <CampaignProgressBar {...args} />,
}

export const WithInProgressAndClosedAlerts = {
  args: {
    openCount: 4,
    closedCount: 4,
    openWithLinksCount: 2,
  },
  render: (args: CampaignProgressBarProps) => <CampaignProgressBar {...args} />,
}

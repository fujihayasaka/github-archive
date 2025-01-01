import type {Meta} from '@storybook/react'
import {CampaignsCountsMetric, type CampaignsCountsMetricProps} from '../CampaignsCountsMetric'

const meta = {
  title: 'Apps/Security Campaigns/Campaigns Counts Metric',
  component: CampaignsCountsMetric,
  argTypes: {},
} satisfies Meta<typeof CampaignsCountsMetric>

export default meta

const defaultArgs: Partial<CampaignsCountsMetricProps> = {
  title: 'Open campaigns',
  campaignsCount: 6,
  totalAlertCount: 620,
  openAlertsCount: 440,
  inProgressAlertsCount: 40,
  fixedAlertsCount: 40,
  dismissedAlertsCount: 10,
}

export const OpenCampaigns = {
  args: {
    ...defaultArgs,
  },
  render: (args: CampaignsCountsMetricProps) => <CampaignsCountsMetric {...args} />,
}

export const ClosedCampaigns = {
  args: {
    ...defaultArgs,
    title: 'Closed campaigns',
    inProgressAlertsCount: undefined,
  },
  render: (args: CampaignsCountsMetricProps) => <CampaignsCountsMetric {...args} />,
}

export const OnlyFewCampaigns = {
  args: {
    ...defaultArgs,
    campaignsCount: 3,
    totalAlertCount: 4,
    openAlertsCount: 2,
    inProgressAlertsCount: undefined,
    fixedAlertsCount: 1,
    dismissedAlertsCount: 1,
  },
  render: (args: CampaignsCountsMetricProps) => <CampaignsCountsMetric {...args} />,
}

export const ManyCampaigns = {
  args: {
    ...defaultArgs,
    campaignsCount: 783,
    totalAlertCount: 487_783,
    openAlertsCount: 283_567,
    inProgressAlertsCount: undefined,
    fixedAlertsCount: 186_378,
    dismissedAlertsCount: 17838,
  },
  render: (args: CampaignsCountsMetricProps) => <CampaignsCountsMetric {...args} />,
}

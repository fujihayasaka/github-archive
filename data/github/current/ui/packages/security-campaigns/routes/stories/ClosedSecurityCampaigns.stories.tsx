import type {Meta} from '@storybook/react'
import {ClosedSecurityCampaigns, type ClosedSecurityCampaignsPayload} from '../ClosedSecurityCampaigns'
import {Wrapper} from '@github-ui/react-core/test-utils'

const meta = {
  title: 'Apps/Security Campaigns/ClosedSecurityCampaigns',
  component: ClosedSecurityCampaigns,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
  argTypes: {},
} satisfies Meta<typeof ClosedSecurityCampaigns>

export default meta

const defaultRoutePayload: ClosedSecurityCampaignsPayload = {
  organizationLogin: 'github',
  closedCampaignsCounts: 25,
  closedCampaignsPath: '/orgs/github/security/campaigns/closed/list',
  closingOrDeletingCampaignsDocsUrl: 'https://example.com/closing-security-campaigns',
  campaignsGAEnabled: false,
  openCampaignsCounts: 5,
  maxOpenCampaigns: 10,
}

export const Loading = {
  render: () => (
    <Wrapper routePayload={defaultRoutePayload}>
      <ClosedSecurityCampaigns />
    </Wrapper>
  ),
}

import type {Meta, StoryObj} from '@storybook/react'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {
  RepositorySecurityCampaignShow,
  type RepositorySecurityCampaignShowPayload,
} from '../RepositorySecurityCampaignShow'
import {createRepository, getIssue, createSecurityCampaignAlert, getSecurityCampaign} from '../../test-utils/mock-data'
import {HttpResponse, http} from 'msw'
import type {GetAlertsResponse} from '../../types/get-alerts-response'
import {BannerProvider} from '@github-ui/role-assignments/banner-provider'

const meta = {
  title: 'Apps/Security Campaigns/RepositorySecurityCampaignShow',
  component: RepositorySecurityCampaignShow,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
    msw: {
      handlers: [
        http.get('/github/security-campaigns/security/campaigns/5/alerts', () => {
          return HttpResponse.json({
            alerts: [
              createSecurityCampaignAlert({number: 1, title: 'Test alert 1', hasSuggestedFix: true}),
              createSecurityCampaignAlert({number: 2, title: 'Test alert 2'}),
            ],
            alertCount: 3,
            openCount: 2,
            closedCount: 1,
            openWithLinksCount: 0,
            nextCursor: '',
            prevCursor: '',
          } satisfies GetAlertsResponse)
        }),
      ],
    },
  },
  argTypes: {},
} satisfies Meta<typeof RepositorySecurityCampaignShow>

export default meta
type Story = StoryObj<typeof RepositorySecurityCampaignShow>

const defaultRoutePayload: RepositorySecurityCampaignShowPayload = {
  campaign: getSecurityCampaign(),
  repository: createRepository(),
  showOrgCampaignLink: true,
  canCreateBranch: true,
  canCloseAlerts: true,
  showHubberWarning: false,
  issue: getIssue(),
  delegatedAlertDismissalEnabled: true,
  assignToCopilotEnabled: true,
}

export const Default: Story = {
  render: () => (
    <Wrapper routePayload={defaultRoutePayload}>
      <BannerProvider>
        <RepositorySecurityCampaignShow />
      </BannerProvider>
    </Wrapper>
  ),
}

export const NoContactLink: Story = {
  render: () => {
    const payload = {
      ...defaultRoutePayload,
      campaign: getSecurityCampaign({contactLink: null}),
    }
    return (
      <Wrapper routePayload={payload}>
        <BannerProvider>
          <RepositorySecurityCampaignShow />
        </BannerProvider>
      </Wrapper>
    )
  },
}

export const NoIssue: Story = {
  render: () => {
    const payload = {
      ...defaultRoutePayload,
      issue: null,
    }
    return (
      <Wrapper routePayload={payload}>
        <BannerProvider>
          <RepositorySecurityCampaignShow />
        </BannerProvider>
      </Wrapper>
    )
  },
}

export const GAAndIssuesDisabled: Story = {
  render: () => {
    const payload = {
      ...defaultRoutePayload,
      issue: null,
    }
    return (
      <Wrapper routePayload={payload}>
        <BannerProvider>
          <RepositorySecurityCampaignShow />
        </BannerProvider>
      </Wrapper>
    )
  },
}

export const HubberWarning: Story = {
  render: () => {
    const payload = {
      ...defaultRoutePayload,
      showHubberWarning: true,
    }
    return (
      <Wrapper routePayload={payload}>
        <BannerProvider>
          <RepositorySecurityCampaignShow />
        </BannerProvider>
      </Wrapper>
    )
  },
}

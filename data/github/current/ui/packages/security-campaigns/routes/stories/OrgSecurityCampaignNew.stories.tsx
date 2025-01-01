import type {Meta} from '@storybook/react'
import {OrgSecurityCampaignNew, type OrgSecurityCampaignNewPayload} from '../OrgSecurityCampaignNew'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {HttpResponse, delay, http} from 'msw'
import {getManyOpenAlerts, getOrgSecurityCampaignNewRoutePayload} from '../../test-utils/mock-data'
import type {GetAlertsResponse} from '../../types/get-alerts-response'

const meta = {
  title: 'Apps/Security Campaigns/New Security Campaign',
  component: OrgSecurityCampaignNew,
  parameters: {
    msw: {
      handlers: [
        http.get('/orgs/github/security/alerts/code-scanning/alert-list', async () => {
          await delay(1000)

          const response: GetAlertsResponse = {
            alerts: getManyOpenAlerts(),
            openCount: 5783,
            closedCount: 783_387,
            openWithLinksCount: 78,
            nextCursor: '',
            prevCursor: '',
          }

          return HttpResponse.json(response)
        }),
      ],
    },
  },
  argTypes: {},
} satisfies Meta<typeof OrgSecurityCampaignNew>

export default meta

const defaultRoutePayload: OrgSecurityCampaignNewPayload = getOrgSecurityCampaignNewRoutePayload()

export const Default = {
  render: () => (
    <Wrapper routePayload={defaultRoutePayload}>
      <OrgSecurityCampaignNew />
    </Wrapper>
  ),
}

export const WithIncompleteDataWarning = {
  render: () => (
    <Wrapper routePayload={{...defaultRoutePayload, showIncompleteDataWarning: true}}>
      <OrgSecurityCampaignNew />
    </Wrapper>
  ),
}

import type {Meta} from '@storybook/react'
import {OrgSecurityCampaignsIndex, type OrgSecurityCampaignsIndexPayload} from '../OrgSecurityCampaignsIndex'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {HttpResponse, delay, http} from 'msw'
import {
  getManyOpenCampaigns,
  getNClosedCampaigns,
  getOrgSecurityCampaignsIndexRoutePayload,
} from '../../test-utils/mock-data'

const meta = {
  title: 'Apps/Security Campaigns/OrgSecurityCampaignsIndex',
  component: OrgSecurityCampaignsIndex,
  parameters: {
    msw: {
      handlers: [
        http.get('/orgs/github/security/campaigns/open/list', async () => {
          await delay(1000)

          return HttpResponse.json({
            campaigns: getManyOpenCampaigns(),
            nextCursor: null,
          })
        }),
        http.get('/orgs/github/security/campaigns/closed/list', async () => {
          await delay(1000)
          return HttpResponse.json({
            campaigns: getNClosedCampaigns(20),
            nextCursor: 'cursornext',
          })
        }),
      ],
    },
  },
  argTypes: {},
} satisfies Meta<typeof OrgSecurityCampaignsIndex>

export default meta

const defaultRoutePayload: OrgSecurityCampaignsIndexPayload = getOrgSecurityCampaignsIndexRoutePayload()

export const Default = {
  render: () => (
    <Wrapper routePayload={defaultRoutePayload}>
      <OrgSecurityCampaignsIndex />
    </Wrapper>
  ),
}

export const BlankSlate = {
  render: () => (
    <Wrapper
      routePayload={{
        ...defaultRoutePayload,
        openCampaignsCount: 0,
        closedCampaignsCount: 0,
        draftCampaignsCount: 0,
      }}
    >
      <OrgSecurityCampaignsIndex />
    </Wrapper>
  ),
}

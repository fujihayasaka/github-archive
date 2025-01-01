import type {Meta} from '@storybook/react'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {HttpResponse, delay, http} from 'msw'
import {getOrgDraftSecurityCampaignPublishRoutePayload} from '../../test-utils/mock-data'
import {
  OrgDraftSecurityCampaignPublish,
  type OrgDraftSecurityCampaignPublishPayload,
} from '../OrgDraftSecurityCampaignPublish'

const meta = {
  title: 'Apps/Security Campaigns/Publish Draft Security Campaign',
  component: OrgDraftSecurityCampaignPublish,
  parameters: {
    msw: {
      handlers: [
        http.post('/orgs/github/security/campaigns/5/publish', async () => {
          await delay(1000)

          return HttpResponse.json(
            {
              message: 'Something went wrong',
            },
            {
              status: 500,
            },
          )
        }),
      ],
    },
  },
  argTypes: {},
} satisfies Meta<typeof OrgDraftSecurityCampaignPublish>

export default meta

const defaultRoutePayload: OrgDraftSecurityCampaignPublishPayload = getOrgDraftSecurityCampaignPublishRoutePayload()

export const Default = {
  render: () => (
    <Wrapper routePayload={defaultRoutePayload}>
      <OrgDraftSecurityCampaignPublish />
    </Wrapper>
  ),
}

export const MaxOpenCampaignsReached = {
  render: () => (
    <Wrapper routePayload={{...defaultRoutePayload, orgOpenCampaignsCount: 10, maxOpenCampaigns: 10}}>
      <OrgDraftSecurityCampaignPublish />
    </Wrapper>
  ),
}

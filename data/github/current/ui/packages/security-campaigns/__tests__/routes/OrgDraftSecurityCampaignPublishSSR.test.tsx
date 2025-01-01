/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {getOrgDraftSecurityCampaignPublishRoutePayload} from '../../test-utils/mock-data'

// Register with react-core before attempting to render
import '../../ssr-entry'

test('renders OrgDraftSecurityCampaignPublish with SSR', async () => {
  const routePayload = getOrgDraftSecurityCampaignPublishRoutePayload()
  const view = await serverRenderReact({
    name: 'security-campaigns',
    path: '/orgs/:owner/security/campaigns/5/publish',
    data: {payload: routePayload},
  })

  // verify ssr was able to render some content from the payload
  expect(view).toMatch('Publish campaign')
})

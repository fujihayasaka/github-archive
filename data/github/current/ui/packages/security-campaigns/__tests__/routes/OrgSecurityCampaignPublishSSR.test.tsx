/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'

// Register with react-core before attempting to render
import '../../ssr-entry'
import {getOrgSecurityCampaignPublishRoutePayload} from '../../test-utils/mock-data'

test('renders OrgSecurityCampaignPublish with SSR', async () => {
  const routePayload = getOrgSecurityCampaignPublishRoutePayload()
  const view = await serverRenderReact({
    name: 'security-campaigns',
    path: '/orgs/github/security/campaigns/publish',
    data: {payload: routePayload},
  })

  // verify ssr was able to render some content from the payload
  expect(view).toMatch('Publish campaign')
})

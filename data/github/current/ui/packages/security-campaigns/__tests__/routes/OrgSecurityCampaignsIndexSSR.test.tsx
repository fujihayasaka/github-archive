/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'

// Register with react-core before attempting to render
import '../../ssr-entry'
import {getOrgSecurityCampaignsIndexRoutePayload} from '../../test-utils/mock-data'

test('Renders security campaigns index page with SSR', async () => {
  const routePayload = getOrgSecurityCampaignsIndexRoutePayload()

  const view = await serverRenderReact({
    name: 'security-campaigns',
    path: '/orgs/:owner/security/campaigns',
    data: {payload: routePayload},
  })

  // verify ssr was able to render some content from the payload
  expect(view).toMatch('Campaigns')
})

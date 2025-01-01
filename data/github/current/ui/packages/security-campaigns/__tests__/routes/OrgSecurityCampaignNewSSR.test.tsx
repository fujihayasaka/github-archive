/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {getOrgSecurityCampaignNewRoutePayload} from '../../test-utils/mock-data'

// Register with react-core before attempting to render
import '../../ssr-entry'

test('Renders OrgSecurityCampaignNew with SSR', async () => {
  const routePayload = getOrgSecurityCampaignNewRoutePayload()
  const view = await serverRenderReact({
    name: 'security-campaigns',
    path: '/orgs/:owner/security/campaigns/new',
    data: {payload: routePayload},
  })

  // verify ssr was able to render some content from the payload
  expect(view).toMatch('Create a new campaign')
})

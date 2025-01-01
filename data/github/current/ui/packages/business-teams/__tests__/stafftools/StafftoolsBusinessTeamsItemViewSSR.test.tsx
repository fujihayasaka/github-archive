/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {getStafftoolsBusinessTeamsItemViewRoutePayload} from '../../test-utils/mock-data'

// Register with react-core before attempting to render
import '../../ssr-entry'

test('Renders BusinessTeamsItemView with SSR', async () => {
  const routePayload = getStafftoolsBusinessTeamsItemViewRoutePayload()
  const view = await serverRenderReact({
    name: 'business-teams',
    path: '/stafftools/enterprises/:slug/enterprise_teams/:teamSlug',
    data: {payload: routePayload},
  })

  // verify ssr was able to render some content from the payload
  expect(view).toMatch(routePayload.enterpriseTeam.name)
})

/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {getBusinessTeamsTableViewRoutePayload} from '../test-utils/mock-data'

// Register with react-core before attempting to render
import '../ssr-entry'

test('Renders BusinessTeamsTableView with SSR', async () => {
  const routePayload = getBusinessTeamsTableViewRoutePayload()
  const view = await serverRenderReact({
    name: 'business-teams',
    path: '/enterprises/:slug/teams',
    data: {payload: routePayload},
  })

  // verify ssr was able to render some content from the payload
  expect(view).toMatch(routePayload.enterpriseTeams?.[0]?.name ?? '')
})

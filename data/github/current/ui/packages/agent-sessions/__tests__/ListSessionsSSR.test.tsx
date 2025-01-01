/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {getListSessionsRoutePayload} from '../test-utils/mock-data'

// Register with react-core before attempting to render
import '../ssr-entry'

test('Renders ListSessions with SSR', async () => {
  const routePayload = getListSessionsRoutePayload()
  const view = await serverRenderReact({
    name: 'agent-sessions',
    path: '/:owner/:repo/sessions',
    data: {
      payload: {
        listSessionsRoute: {
          mainQuery: routePayload,
        },
      },
    },
    data_router_enabled: true,
  })

  // verify ssr was able to render some content from the payload
  expect(view).toMatch(routePayload.sessions[0]!.id)
})

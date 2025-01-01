/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {getHypersightRoutePayload} from '../test-utils/mock-data'

// Register with react-core before attempting to render
import '../entry'

test('Renders Hypersight with SSR', async () => {
  const routePayload = getHypersightRoutePayload()
  const view = await serverRenderReact({
    name: 'hypersight',
    path: '/:user_id/:repository/pull/:id/walkthrough',
    data: {payload: routePayload},
  })

  // verify ssr was able to render some content from the payload
  expect(view).toContain(routePayload.pullRequest.title)
})

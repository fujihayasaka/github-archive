/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {getHomeRoutePayload} from '../test-utils/mock-data'

// Register with react-core before attempting to render
import '../ssr-entry'

test('Renders Home with SSR', async () => {
  const routePayload = getHomeRoutePayload()
  const view = await serverRenderReact({
    name: 'brand-pages',
    path: '/',
    data: {payload: routePayload},
  })

  // verify ssr was able to render some content from the payload
  expect(view).toMatch(routePayload.someField)
})

/** @jest-environment node */
// Register with react-core before attempting to render
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {getShowAppRoutePayload} from '../test-utils/mock-data'
import '../ssr-entry'
import {mockAppListing} from '@github-ui/marketplace-common/mock-data'

test('Renders Marketplace app page with SSR', async () => {
  const view = await serverRenderReact({
    name: 'marketplace-react',
    path: '/marketplace/example-app',
    data: {
      payload: getShowAppRoutePayload({listing: mockAppListing({name: 'Example App', slug: 'example-app'})}),
    },
  })
  expect(view).toMatch('Example App')
})

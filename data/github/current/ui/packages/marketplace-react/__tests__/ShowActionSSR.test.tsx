/** @jest-environment node */
// Register with react-core before attempting to render
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {getShowActionRoutePayload} from '../test-utils/mock-data'
import '../ssr-entry'
import {mockActionListing} from '@github-ui/marketplace-common/mock-data'

test('Renders Marketplace action page with SSR', async () => {
  const view = await serverRenderReact({
    name: 'marketplace-react',
    path: '/marketplace/actions/example-action',
    data: {
      payload: getShowActionRoutePayload({
        action: mockActionListing({name: 'Example Action', slug: 'example-action'}),
      }),
    },
  })
  expect(view).toMatch('Example Action')
})

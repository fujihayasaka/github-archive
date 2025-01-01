/** @jest-environment node */
// Register with react-core before attempting to render
import {getIndexRoutePayload} from '@github-ui/marketplace-common/mock-data'
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import '../ssr-entry'

test('Renders Marketplace with SSR', async () => {
  const view = await serverRenderReact({
    name: 'marketplace-react',
    path: '/marketplace',
    data: {
      payload: getIndexRoutePayload(),
    },
  })

  // should only show up on index page
  expect(view).toMatch('Featured')
})

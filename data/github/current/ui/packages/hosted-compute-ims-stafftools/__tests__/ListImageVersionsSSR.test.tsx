/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {getListImageVersionsRoutePayload} from '../test-utils/mock-data'

// Register with react-core before attempting to render
import '../ssr-entry'

test('Renders ListImageVersions with SSR', async () => {
  const routePayload = getListImageVersionsRoutePayload()
  const view = await serverRenderReact({
    name: 'hosted-compute-ims-stafftools',
    path: '/stafftools/hosted_compute_ims_admin/curated/:image_definition_id',
    data: {payload: routePayload},
  })

  // verify ssr was able to render some content from the payload
  expect(view).toMatch('Curated images')
})

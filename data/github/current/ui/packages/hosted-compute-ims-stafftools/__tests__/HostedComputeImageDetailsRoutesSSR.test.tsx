/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'

// Register with react-core before attempting to render
import '../ssr-entry'
import {getListImageVersionsRoutePayload} from '../test-utils/mock-data'
import {Constants} from '../helpers/constants'

describe('HostedComputeImageDetails routes', () => {
  it('renders image details page with SSR', async () => {
    const payload = {hostedComputeImageDetailsRoute: getListImageVersionsRoutePayload()}

    const view = await serverRenderReact({
      name: 'hosted-compute-ims-stafftools',
      path: '/stafftools/hosted_compute_ims_admin/curated_images/1',
      data: {payload},
      data_router_enabled: true,
    })

    // Verify SSR was able to render key content from the payload
    expect(view).toMatch(Constants.stafftoolPageTitle)
    expect(view).toMatch('test-name-1 (ID 1)')
    expect(view).toMatch('GitHub images')
    expect(view).toMatch('1.0.0')
    expect(view).toMatch('Image Gen Enabled:')
  })
})

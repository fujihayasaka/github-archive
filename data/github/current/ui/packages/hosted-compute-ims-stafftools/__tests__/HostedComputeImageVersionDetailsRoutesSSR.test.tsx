/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'

// Register with react-core before attempting to render
import '../ssr-entry'
import {getImageVersionDetailsRoutePayload} from '../test-utils/mock-data'
import {Constants} from '../helpers/constants'

describe('HostedComputeImageVersionDetails routes', () => {
  it('renders image version details page with SSR', async () => {
    const payload = {hostedComputeImageVersionDetailsRoute: getImageVersionDetailsRoutePayload()}

    const view = await serverRenderReact({
      name: 'hosted-compute-ims-stafftools',
      path: '/stafftools/hosted_compute_ims_admin/curated_images/1/versions/1.0.0',
      data: {payload},
      data_router_enabled: true,
    })

    // Verify SSR was able to render key content from the payload
    expect(view).toMatch(Constants.stafftoolPageTitle)
    expect(view).toMatch('test-name-1 (ID 1)')
    expect(view).toMatch('1.0.0')
  })
})

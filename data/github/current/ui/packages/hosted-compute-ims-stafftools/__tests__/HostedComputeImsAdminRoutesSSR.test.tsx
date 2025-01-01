/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'

// Register with react-core before attempting to render
import '../ssr-entry'
import {getMainRoutePayload} from '../test-utils/mock-data'
import {Constants} from '../helpers/constants'

describe('HostedComputeImsAdmin routes', () => {
  it('renders admin page with SSR', async () => {
    const payload = {hostedComputeImsAdminRoute: getMainRoutePayload()}

    const view = await serverRenderReact({
      name: 'hosted-compute-ims-stafftools',
      path: '/stafftools/hosted_compute_ims_admin',
      data: {payload},
      data_router_enabled: true,
    })

    // Verify SSR was able to render key content from the payload
    expect(view).toMatch(Constants.stafftoolPageTitle)
    expect(view).toMatch(Constants.githubOwnedImagesTabTitle)
  })
})

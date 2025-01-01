import {getMainRoutePayload} from '../test-utils/mock-data'
import {render} from '@github-ui/react-core/future/test-utils/render'
import {hostedComputeImsStafftoolsApp} from '../hosted-compute-ims-stafftools'
import {screen} from '@testing-library/react'
import {Constants} from '../helpers/constants'

describe('HostedComputeImsAdmin routes', () => {
  it('renders admin page with CSR from embedded data', async () => {
    const payload = {hostedComputeImsAdminRoute: getMainRoutePayload()}
    render(hostedComputeImsStafftoolsApp, '/stafftools/hosted_compute_ims_admin', {
      embeddedData: {
        payload,
        meta: {
          title: 'Hosted Compute IMS',
        },
      },
    })

    expect(await screen.findByText(Constants.stafftoolPageTitle)).toBeInTheDocument()
    expect(screen.getByText(Constants.githubOwnedImagesTabTitle)).toBeInTheDocument()
  })
})

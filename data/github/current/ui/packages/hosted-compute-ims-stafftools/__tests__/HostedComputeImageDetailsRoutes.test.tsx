import {getListImageVersionsRoutePayload} from '../test-utils/mock-data'
import {render} from '@github-ui/react-core/future/test-utils/render'
import {hostedComputeImsStafftoolsApp} from '../hosted-compute-ims-stafftools'
import {screen} from '@testing-library/react'
import {Constants} from '../helpers/constants'

describe('HostedComputeImageDetails routes', () => {
  it('renders image details page with CSR from embedded data', async () => {
    const payload = {hostedComputeImageDetailsRoute: getListImageVersionsRoutePayload()}
    render(hostedComputeImsStafftoolsApp, '/stafftools/hosted_compute_ims_admin/curated_images/1', {
      embeddedData: {
        payload,
        meta: {
          title: 'Hosted Compute IMS',
        },
      },
    })

    expect(await screen.findByText(Constants.stafftoolPageTitle)).toBeInTheDocument()
    expect(screen.getByText('test-name-1 (ID 1)')).toBeInTheDocument()
    expect(screen.getByText('GitHub images')).toBeInTheDocument()
    expect(screen.getByText('1.0.0')).toBeInTheDocument()
    expect(screen.getByText('Image Gen Enabled:')).toBeInTheDocument()
  })
})

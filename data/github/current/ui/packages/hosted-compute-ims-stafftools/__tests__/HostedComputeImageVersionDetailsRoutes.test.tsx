import {getImageVersionDetailsRoutePayload} from '../test-utils/mock-data'
import {render} from '@github-ui/react-core/future/test-utils/render'
import {hostedComputeImsStafftoolsApp} from '../hosted-compute-ims-stafftools'
import {screen} from '@testing-library/react'
import {Constants} from '../helpers/constants'

describe('HostedComputeImageVersionDetails routes', () => {
  it('renders image version details page with CSR from embedded data', async () => {
    const payload = {hostedComputeImageVersionDetailsRoute: getImageVersionDetailsRoutePayload()}
    render(hostedComputeImsStafftoolsApp, '/stafftools/hosted_compute_ims_admin/curated_images/1/versions/1.0.0', {
      embeddedData: {
        payload,
        meta: {
          title: 'Hosted Compute IMS',
        },
      },
    })

    expect(await screen.findByText(Constants.stafftoolPageTitle)).toBeInTheDocument()
    expect(screen.getByText('test-name-1 (ID 1)')).toBeInTheDocument()
    const versionElements = screen.getAllByText('1.0.0')
    expect(versionElements.length).toBeGreaterThanOrEqual(2)
    for (const el of versionElements) {
      expect(el).toBeInTheDocument()
    }
  })
})

import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {EnterpriseCloudDetails} from '../EnterpriseCloudDetails'
import {getLicensingEnterpriseCloudDetailsProps} from '../test-utils/mock-data'

test('Renders the LicensingEnterpriseCloudDetails', () => {
  const props = getLicensingEnterpriseCloudDetailsProps()
  render(<EnterpriseCloudDetails {...props} />)
  expect(screen.getByTestId('licensing-cloud-details')).toBeInTheDocument()
})

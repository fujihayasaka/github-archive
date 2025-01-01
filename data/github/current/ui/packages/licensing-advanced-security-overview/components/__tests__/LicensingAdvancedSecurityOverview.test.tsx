import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {LicensingAdvancedSecurityOverview} from '../LicensingAdvancedSecurityOverview'
import {getLicensingAdvancedSecurityOverviewProps} from '../../test-utils/mock-data'

describe('LicensingAdvancedSecurityOverview Component', () => {
  test('Renders the LicensingAdvancedSecurityOverview', () => {
    const props = getLicensingAdvancedSecurityOverviewProps()
    render(<LicensingAdvancedSecurityOverview {...props} />)
    expect(screen.getByTestId('licensing-advanced-security-overview')).toBeInTheDocument()
  })
})

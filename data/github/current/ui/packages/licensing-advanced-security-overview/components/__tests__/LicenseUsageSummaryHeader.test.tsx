import {render, screen} from '@testing-library/react'
import {getLicenseUsageSummaryHeaderProps} from '../../test-utils/mock-data'
import {LicenseUsageSummaryHeader} from '../LicenseUsageSummaryHeader'

const renderLicenseUsageSummaryHeader = (overrideProps = {}) => {
  return render(<LicenseUsageSummaryHeader {...getLicenseUsageSummaryHeaderProps()} {...overrideProps} />)
}

describe('LicenseUsageSummaryHeader Component', () => {
  test('renders the header UI elements', () => {
    renderLicenseUsageSummaryHeader()

    const summaryHeaderTitleEl = screen.queryByTestId('usage-summary-header-title')
    expect(summaryHeaderTitleEl).toBeInTheDocument()
    expect(summaryHeaderTitleEl).toHaveTextContent('Consumed licenses')
  })
})

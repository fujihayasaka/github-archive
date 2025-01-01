import {render, screen} from '@testing-library/react'
import {LicenseUsageSummaryItem} from '../LicenseUsageSummaryItem'
import {getLicenseUsageSummaryItemProps} from '../../test-utils/mock-data'

const renderLicenseUsageSummaryItem = (overrideProps = {}) => {
  return render(<LicenseUsageSummaryItem {...getLicenseUsageSummaryItemProps()} {...overrideProps} />)
}

describe('LicenseUsageSummaryItem Component', () => {
  test('renders the summary item UI elements', () => {
    renderLicenseUsageSummaryItem()

    const summaryItemAmtEl = screen.queryByTestId('summary-item-amount')
    expect(summaryItemAmtEl).toBeInTheDocument()
    expect(summaryItemAmtEl).toHaveTextContent('5')

    const summaryItemDescEl = screen.queryByTestId('summary-amount-desc')
    expect(summaryItemDescEl).toBeInTheDocument()
    expect(summaryItemDescEl).toHaveTextContent('Secret Protection and Code Security licenses')

    const progressBarEl = screen.queryByTestId('seat-count-progress-bar')
    expect(progressBarEl).not.toBeInTheDocument()
  })

  test('renders the progress bar', () => {
    renderLicenseUsageSummaryItem({isVolumeLicensed: true})

    const progressBarEl = screen.queryByTestId('seat-count-progress-bar')
    expect(progressBarEl).toBeInTheDocument()

    const availableLicensesEl = screen.queryByTestId('available-licenses-count')
    expect(availableLicensesEl).toBeInTheDocument()
    expect(availableLicensesEl).toHaveTextContent('19 available')
  })

  test('does not render the progress bar for metered business', () => {
    renderLicenseUsageSummaryItem({isVolumeLicensed: false})

    expect(screen.queryByTestId('seat-count-progress-bar')).not.toBeInTheDocument()
  })

  test('renders the number of available licenses if trial', () => {
    renderLicenseUsageSummaryItem({isVolumeLicensed: false, unlimitedLicense: true, isTrial: true})

    const availableLicensesEl = screen.queryByTestId('available-licenses-count')
    expect(availableLicensesEl).toBeInTheDocument()
  })

  test('does not render the number of available licenses if unlimited', () => {
    renderLicenseUsageSummaryItem({isVolumeLicensed: true, unlimitedLicense: true})

    const availableLicensesEl = screen.queryByTestId('available-licenses-count')
    expect(availableLicensesEl).not.toBeInTheDocument()
  })

  test('does not render the number of available licenses if zero', () => {
    renderLicenseUsageSummaryItem({isVolumeLicensed: true, purchasedLicenses: 0})

    const availableLicensesEl = screen.queryByTestId('available-licenses-count')
    expect(availableLicensesEl).not.toBeInTheDocument()
  })
})

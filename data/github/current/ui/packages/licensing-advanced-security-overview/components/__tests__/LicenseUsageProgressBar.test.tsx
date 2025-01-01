import {render, screen} from '@testing-library/react'
import {LicenseUsageProgressBar} from '../LicenseUsageProgressBar'
import {getLicenseUsageProgressBarProps} from '../../test-utils/mock-data'

const renderLicenseUsageProgressBar = (overrideProps = {}) => {
  return render(<LicenseUsageProgressBar {...getLicenseUsageProgressBarProps()} {...overrideProps} />)
}

describe('LicenseUsageProgressBar Component', () => {
  test('renders the progress bar UI elements', () => {
    renderLicenseUsageProgressBar()

    const progressBarEl = screen.queryByTestId('license-usage-progress')
    expect(progressBarEl).toBeInTheDocument()
    expect(progressBarEl).toHaveAttribute('aria-valuenow', '26')
    expect(progressBarEl).toHaveAttribute('aria-valuetext', '5 licenses used.')
  })
})

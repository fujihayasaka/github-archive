import {render, screen} from '@testing-library/react'
import {NavigationContextProvider} from '../../contexts/NavigationContext'
import {type Props as EnterpriseCloudSeatCountProps, EnterpriseCloudSeatCount} from '../EnterpriseCloudSeatCount'

const defaultProps: EnterpriseCloudSeatCountProps = {
  canViewMembers: true,
  isTrial: false,
  isVolumeLicensed: false,
  enterpriseLicensesConsumed: 0,
  enterpriseLicensesPurchased: 0,
  vssLicensesConsumed: 0,
  vssLicensesPurchasedWithOverage: 0,
}
const renderSeatCount = (overrideProps = {}, isStafftools = false) => {
  return render(
    <NavigationContextProvider
      enterpriseContactUrl={'/enterprise-contact-url'}
      isStafftools={isStafftools}
      slug={'test-co'}
      isTeams={false}
    >
      <EnterpriseCloudSeatCount {...defaultProps} {...overrideProps} />
    </NavigationContextProvider>,
  )
}

describe('EnterpriseCloudSeatCount Component', () => {
  describe('Metered-licensed, non-trial', () => {
    test('renders seat count with no limit view', () => {
      renderSeatCount({isTrial: false, isVolumeLicensed: false, enterpriseLicensesConsumed: 123})

      const seatCountEl = screen.queryByTestId('seat-count-used-no-limit')
      expect(seatCountEl).toBeInTheDocument()
      expect(seatCountEl).toHaveTextContent('123')
    })
  })

  describe('Metered-licensed, trial', () => {
    test('renders seat count with limit view', () => {
      renderSeatCount({
        isTrial: true,
        isVolumeLicensed: false,
        enterpriseLicensesConsumed: 1234,
        enterpriseLicensesPurchased: 5678,
      })

      const totalConsumedEl = screen.queryByTestId('seat-count-total-consumed')
      expect(totalConsumedEl).toBeInTheDocument()
      expect(totalConsumedEl).toHaveTextContent('1,234')

      const totalPurchasedEl = screen.queryByTestId('seat-count-total-purchased')
      expect(totalPurchasedEl).toBeInTheDocument()
      expect(totalPurchasedEl).toHaveTextContent('5,678 available')

      const progressBarEl = screen.queryByTestId('seat-count-progress-bar')
      expect(progressBarEl).toBeInTheDocument()

      const progressBarEnterpriseEl = screen.queryByTestId('seat-count-progress-enterprise')
      expect(progressBarEnterpriseEl).toHaveAttribute('aria-valuetext', '1,234 Enterprise licenses used.')

      const enterpriseProgressEl = screen.queryByTestId('seat-count-progress-enterprise')
      expect(enterpriseProgressEl).toBeInTheDocument()

      const vssProgressEl = screen.queryByTestId('seat-count-progress-vss')
      expect(vssProgressEl).not.toBeInTheDocument()

      const legendEl = screen.queryByTestId('seat-count-legend')
      expect(legendEl).not.toBeInTheDocument()
    })
  })

  describe('Volume-licensed, non-trial, no VSS bundle', () => {
    test('renders seat count with limit view', () => {
      renderSeatCount({
        isTrial: false,
        isVolumeLicensed: true,
        enterpriseLicensesConsumed: 1234,
        enterpriseLicensesPurchased: 5678,
        vssLicensesConsumed: 0,
        vssLicensesPurchasedWithOverage: 0,
      })

      const totalConsumedEl = screen.queryByTestId('seat-count-total-consumed')
      expect(totalConsumedEl).toBeInTheDocument()
      expect(totalConsumedEl).toHaveTextContent('1,234')

      const totalPurchasedEl = screen.queryByTestId('seat-count-total-purchased')
      expect(totalPurchasedEl).toBeInTheDocument()
      expect(totalPurchasedEl).toHaveTextContent('5,678 available')

      const progressBarEnterpriseEl = screen.queryByTestId('seat-count-progress-enterprise')
      expect(progressBarEnterpriseEl).toBeInTheDocument()
      expect(progressBarEnterpriseEl).toHaveAttribute('aria-valuetext', '1,234 Enterprise licenses used.')

      const enterpriseProgressEl = screen.queryByTestId('seat-count-progress-enterprise')
      expect(enterpriseProgressEl).toBeInTheDocument()

      const vssProgressEl = screen.queryByTestId('seat-count-progress-vss')
      expect(vssProgressEl).not.toBeInTheDocument()

      const legendEl = screen.queryByTestId('seat-count-legend')
      expect(legendEl).not.toBeInTheDocument()
    })
  })

  describe('Volume-licensed, trial, no VSS bundle', () => {
    test('renders seat count with limit view', () => {
      renderSeatCount({
        isTrial: true,
        isVolumeLicensed: true,
        enterpriseLicensesConsumed: 123,
        enterpriseLicensesPurchased: 234,
        vssLicensesConsumed: 0,
        vssLicensesPurchasedWithOverage: 0,
      })

      const totalConsumedEl = screen.queryByTestId('seat-count-total-consumed')
      expect(totalConsumedEl).toBeInTheDocument()
      expect(totalConsumedEl).toHaveTextContent('123')

      const totalPurchasedEl = screen.queryByTestId('seat-count-total-purchased')
      expect(totalPurchasedEl).toBeInTheDocument()
      expect(totalPurchasedEl).toHaveTextContent('234 available')

      const progressBarEl = screen.queryByTestId('seat-count-progress-bar')
      expect(progressBarEl).toBeInTheDocument()

      const progressBarEnterpriseEl = screen.queryByTestId('seat-count-progress-enterprise')
      expect(progressBarEnterpriseEl).toHaveAttribute('aria-valuetext', '123 Enterprise licenses used.')

      const enterpriseProgressEl = screen.queryByTestId('seat-count-progress-enterprise')
      expect(enterpriseProgressEl).toBeInTheDocument()

      const vssProgressEl = screen.queryByTestId('seat-count-progress-vss')
      expect(vssProgressEl).not.toBeInTheDocument()

      const legendEl = screen.queryByTestId('seat-count-legend')
      expect(legendEl).not.toBeInTheDocument()
    })
  })

  describe('Volume-licensed, non-trial, with VSS bundle', () => {
    test('renders seat count with limit view', () => {
      renderSeatCount({
        isTrial: false,
        isVolumeLicensed: true,
        enterpriseLicensesConsumed: 1000,
        enterpriseLicensesPurchased: 2000,
        vssLicensesConsumed: 3000,
        vssLicensesPurchasedWithOverage: 4000,
      })

      const totalConsumedEl = screen.queryByTestId('seat-count-total-consumed')
      expect(totalConsumedEl).toBeInTheDocument()
      expect(totalConsumedEl).toHaveTextContent('4,000')

      const totalPurchasedEl = screen.queryByTestId('seat-count-total-purchased')
      expect(totalPurchasedEl).toBeInTheDocument()
      expect(totalPurchasedEl).toHaveTextContent('6,000 available')

      const progressBarEl = screen.queryByTestId('seat-count-progress-bar')
      expect(progressBarEl).toBeInTheDocument()

      const progressBarEnterpriseEl = screen.queryByTestId('seat-count-progress-enterprise')
      const progressBarVssEl = screen.queryByTestId('seat-count-progress-vss')

      expect(progressBarEnterpriseEl).toHaveAttribute('aria-valuetext', '1,000 Enterprise licenses used.')
      expect(progressBarVssEl).toHaveAttribute('aria-valuetext', '3,000 Visual Studio licenses used.')

      const enterpriseProgressEl = screen.queryByTestId('seat-count-progress-enterprise')
      expect(enterpriseProgressEl).toBeInTheDocument()

      const vssProgressEl = screen.queryByTestId('seat-count-progress-vss')
      expect(vssProgressEl).toBeInTheDocument()

      const legendEl = screen.queryByTestId('seat-count-legend')
      expect(legendEl).toBeInTheDocument()

      const legendEnterpriseCount = screen.queryByTestId('seat-count-legend-enterprise-count')
      expect(legendEnterpriseCount).toBeInTheDocument()
      expect(legendEnterpriseCount).toHaveTextContent('1,000')

      const legendVssCount = screen.queryByTestId('seat-count-legend-vss-count')
      expect(legendVssCount).toBeInTheDocument()
      expect(legendVssCount).toHaveTextContent('3,000')
    })
  })
})

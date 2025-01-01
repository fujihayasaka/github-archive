import {render, screen} from '@testing-library/react'
import {AnalyticsProvider} from '@github-ui/analytics-provider'
import {NavigationContextProvider} from '../../contexts/NavigationContext'
import {EnterpriseCloudSummary} from '../EnterpriseCloudSummary'
import {getEnterpriseCloudSummaryProps} from '../../test-utils/mock-data'

const analyticsMetadata = {}
const renderEnterpriseCloudSummary = (overrideProps = {}) => {
  return render(
    <AnalyticsProvider appName={'test-app'} category="test-analytics-category" metadata={analyticsMetadata}>
      <NavigationContextProvider enterpriseContactUrl={'/enterprise-contact-url'} isStafftools={false} slug={'test-co'}>
        <EnterpriseCloudSummary {...getEnterpriseCloudSummaryProps()} {...overrideProps} />
      </NavigationContextProvider>
    </AnalyticsProvider>,
  )
}

describe('EnterpriseCloudSummary Component', () => {
  test('Current payment displays correct amount', () => {
    renderEnterpriseCloudSummary({currentPayment: 1000})
    expect(screen.getByText('1000')).toBeInTheDocument()
  })

  describe('Variant: Active (No Trial)', () => {
    test('renders summary card with active state', () => {
      renderEnterpriseCloudSummary({trialInfo: undefined})

      const trialLabelEl = screen.queryByTestId('summary-card-active-trial-label')
      expect(trialLabelEl).not.toBeInTheDocument()
    })

    test('renders active footer', () => {
      renderEnterpriseCloudSummary({
        billingTermEndDate: new Date('2024-05-12T00:00:00.000-07:00'),
        trialInfo: undefined,
      })

      const footerEl = screen.queryByTestId('ghe-summary-active-footer')
      expect(footerEl).toBeInTheDocument()
      expect(footerEl).toHaveTextContent('Billing date on May 12, 2024.')
    })
  })

  describe('Variant: Active Trial', () => {
    const activeTrialInfo = {
      isActive: true,
      expirationDate: new Date('2024-05-12T00:00:00.000-07:00'),
      trialLicensesAllowed: 42,
    }

    test('renders card with active trial state', () => {
      renderEnterpriseCloudSummary({trialInfo: activeTrialInfo})

      const trialLabelEl = screen.queryByTestId('summary-card-label-trial')
      expect(trialLabelEl).toBeInTheDocument()
    })

    test('renders trial footer', () => {
      renderEnterpriseCloudSummary({trialInfo: activeTrialInfo})

      const footerEl = screen.queryByTestId('ghe-summary-trial-footer')
      expect(footerEl).toBeInTheDocument()
      expect(footerEl).toHaveTextContent('Trial ends on May 12, 2024.')
    })
  })

  describe('Variant: Expired Trial', () => {
    const expiredTrialInfo = {
      isActive: false,
      expirationDate: new Date('2024-05-12T00:00:00.000-07:00'),
    }

    test('renders card with expired trial state', () => {
      renderEnterpriseCloudSummary({trialInfo: expiredTrialInfo})

      const trialLabelEl = screen.queryByTestId('summary-card-label-trial-expired')
      expect(trialLabelEl).toBeInTheDocument()
    })

    test('when trialInfo is provided, renders trial footer', () => {
      renderEnterpriseCloudSummary({trialInfo: expiredTrialInfo})

      const footerEl = screen.queryByTestId('ghe-summary-trial-footer')
      expect(footerEl).toBeInTheDocument()
      expect(footerEl).toHaveTextContent('Trial ended on May 12, 2024.')
    })
  })

  describe('Payment Info', () => {
    test('payment info section is shown for self-serve', () => {
      renderEnterpriseCloudSummary({isSelfServe: true})
      expect(screen.getByTestId('payment-info')).toBeInTheDocument()
    })

    test('payment info section is not shown for non-self-serve', () => {
      renderEnterpriseCloudSummary({isSelfServe: false})
      expect(screen.queryByTestId('payment-info')).not.toBeInTheDocument()
    })
  })

  describe('Invoice License Info', () => {
    const invoiceLicenseInfo = (type: string) => ({actionType: type})
    const invoiceLicenseInfoWithStatusMessage = (type: string, variant: string) => ({
      ...invoiceLicenseInfo(type),
      statusMessage: {variant},
    })

    test('upgrade action type', () => {
      renderEnterpriseCloudSummary({trialInfo: undefined, invoiceLicenseInfo: invoiceLicenseInfo('upgrade')})
      const footer = screen.getByTestId('ghe-summary-invoice-license-footer')
      expect(footer).toBeInTheDocument()
      expect(footer).toHaveTextContent('Add seats')
    })

    test('renewal action type', () => {
      renderEnterpriseCloudSummary({trialInfo: undefined, invoiceLicenseInfo: invoiceLicenseInfo('renewal')})
      const footer = screen.getByTestId('ghe-summary-invoice-license-footer')
      expect(footer).toBeInTheDocument()
      expect(footer).toHaveTextContent('Renew Enterprise Cloud')
    })

    test('unknown action type', () => {
      renderEnterpriseCloudSummary({trialInfo: undefined, invoiceLicenseInfo: invoiceLicenseInfo('unknown')})
      const footer = screen.queryByTestId('ghe-summary-invoice-license-footer')
      expect(footer).not.toBeInTheDocument()
    })

    test('contact sales for error', () => {
      renderEnterpriseCloudSummary({
        trialInfo: undefined,
        invoiceLicenseInfo: invoiceLicenseInfoWithStatusMessage('renewal', 'critical'),
      })
      const footer = screen.getByTestId('ghe-summary-invoice-license-footer')
      expect(footer).toBeInTheDocument()
      expect(footer).toHaveTextContent('Contact sales')
    })

    test('empty invoice license info', () => {
      renderEnterpriseCloudSummary({trialInfo: undefined})
      const footer = screen.queryByTestId('ghe-summary-invoice-license-footer')
      expect(footer).not.toBeInTheDocument()
    })

    test('does not show for trial', () => {
      renderEnterpriseCloudSummary({trialInfo: {}, invoiceLicenseInfo: invoiceLicenseInfo('renewal')})
      const footer = screen.queryByTestId('ghe-summary-invoice-license-footer')
      expect(footer).not.toBeInTheDocument()
    })
  })

  describe('Manage Seats', () => {
    test('Shows monthly label if business is billed monthly', () => {
      renderEnterpriseCloudSummary({
        isManagingSeats: true,
        isMonthly: true,
        isSelfServe: true,
        isVolumeLicensed: true,
        trialInfo: undefined,
      })

      const paymentTermLabel = screen.getByTestId('payment-term-label')
      expect(paymentTermLabel).toBeInTheDocument()
      expect(paymentTermLabel).toHaveTextContent('Monthly payment')
    })

    test('Shows yearly label if business is billed yearly', () => {
      renderEnterpriseCloudSummary({
        isManagingSeats: true,
        isMonthly: false,
        isSelfServe: true,
        isVolumeLicensed: true,
        trialInfo: undefined,
      })

      const paymentTermLabel = screen.getByTestId('payment-term-label')
      expect(paymentTermLabel).toBeInTheDocument()
      expect(paymentTermLabel).toHaveTextContent('Yearly payment')
    })
  })

  describe('Invoice License Expiration', () => {
    test('displays the correct formatted date', () => {
      const mockDate = new Date('2024-05-01T00:00:00.000Z').getTime()
      jest.spyOn(Date, 'now').mockImplementation(() => mockDate)

      renderEnterpriseCloudSummary({
        billingTermEndDate: new Date('2025-05-12T00:00:00.000-07:00'),
        trialInfo: undefined,
        isSelfServe: false,
      })

      const expiration = screen.getByTestId('ghe-summary-invoice-license-expiration')
      const date = screen.getByTestId('ghe-summary-formatted-date')
      expect(expiration).toBeInTheDocument()
      expect(expiration).toHaveTextContent('Valid until')
      expect(date).toBeInTheDocument()
      expect(date).toHaveTextContent('May 12, 2025')

      jest.restoreAllMocks()
    })

    test('shows "Expired" label when the date is expired', () => {
      const mockDate = new Date('2024-05-01T00:00:00.000Z').getTime()
      jest.spyOn(Date, 'now').mockImplementation(() => mockDate)

      renderEnterpriseCloudSummary({
        billingTermEndDate: new Date('2020-05-12T00:00:00.000-07:00'),
        trialInfo: undefined,
        isSelfServe: false,
      })

      const expiration = screen.getByTestId('ghe-summary-invoice-license-expiration')
      const expired = screen.getByTestId('ghe-summary-expired-label')
      expect(expiration).toBeInTheDocument()
      expect(expired).toBeInTheDocument()

      jest.restoreAllMocks()
    })

    test('shows support and updates message when the date is not expired', () => {
      const mockDate = new Date('2025-05-01T00:00:00.000Z').getTime()
      jest.spyOn(Date, 'now').mockImplementation(() => mockDate)

      renderEnterpriseCloudSummary({
        billingTermEndDate: new Date('2025-05-12T00:00:00.000-07:00'),
        trialInfo: undefined,
        isSelfServe: false,
      })

      const expiration = screen.getByTestId('ghe-summary-invoice-license-expiration')
      const support = screen.getByTestId('ghe-summary-support-and-updates-notice')
      expect(expiration).toBeInTheDocument()
      expect(support).toBeInTheDocument()
      expect(support).toHaveTextContent('includes support and updates')

      jest.restoreAllMocks()
    })

    test('applies correct CSS class when expired', () => {
      const mockDate = new Date('2025-05-01T00:00:00.000Z').getTime()
      jest.spyOn(Date, 'now').mockImplementation(() => mockDate)

      renderEnterpriseCloudSummary({
        billingTermEndDate: new Date('2020-05-12T00:00:00.000-07:00'),
        trialInfo: undefined,
        isSelfServe: false,
      })

      const expiration = screen.getByTestId('ghe-summary-invoice-license-expiration')
      expect(expiration).toBeInTheDocument()

      const expired = screen.getByTestId('ghe-summary-expired-label')
      expect(expired).toHaveTextContent('Expired')

      jest.restoreAllMocks()
    })

    test('applies correct CSS class when not expired', () => {
      const mockDate = new Date('2025-05-01T00:00:00.000Z').getTime()
      jest.spyOn(Date, 'now').mockImplementation(() => mockDate)

      renderEnterpriseCloudSummary({
        billingTermEndDate: new Date('2025-05-12T00:00:00.000-07:00'),
        trialInfo: undefined,
        isSelfServe: false,
      })

      const expiration = screen.getByTestId('ghe-summary-invoice-license-expiration')
      expect(expiration).toBeInTheDocument()

      const support = screen.getByTestId('ghe-summary-support-and-updates-notice')
      expect(support).toHaveClass('fgColor-muted')

      jest.restoreAllMocks()
    })
  })
})

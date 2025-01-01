import {render, screen} from '@testing-library/react'
import {AnalyticsProvider} from '@github-ui/analytics-provider'
import {NavigationContextProvider} from '@github-ui/licensing-common/contexts/NavigationContext'
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
    test('payment info section is rendered', () => {
      renderEnterpriseCloudSummary({isSelfServe: true})
      expect(screen.getByTestId('payment-info')).toBeInTheDocument()
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
      expect(footer).toHaveTextContent('Add licenses')
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
})

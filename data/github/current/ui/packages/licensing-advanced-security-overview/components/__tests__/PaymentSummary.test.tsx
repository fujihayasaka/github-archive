import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {getPaymentSummaryProps} from '../../test-utils/mock-data'
import {PaymentSummary} from '../PaymentSummary'

const renderPaymentSummary = (overrideProps = {}) => {
  return render(<PaymentSummary {...getPaymentSummaryProps()} {...overrideProps} />)
}

describe('PaymentSummary Component', () => {
  test('renders the title for metered bundled', () => {
    renderPaymentSummary()

    const titleEl = screen.queryByTestId('payment-summary-title')
    expect(titleEl).toBeInTheDocument()

    expect(titleEl).toHaveTextContent('Estimated next payment')
  })

  test('renders the yearly title for volume bundled', () => {
    renderPaymentSummary({isMeteredLicensed: false, billingCycle: 'Yearly'})
    const yearlyTitleEl = screen.queryByTestId('payment-summary-title')
    expect(yearlyTitleEl).toBeInTheDocument()
    expect(yearlyTitleEl).toHaveTextContent('Yearly payment')
  })

  test('renders the monthly title for volume bundled', () => {
    renderPaymentSummary({isMeteredLicensed: false})
    const monthlyTitleEl = screen.queryByTestId('payment-summary-title')
    expect(monthlyTitleEl).toBeInTheDocument()
    expect(monthlyTitleEl).toHaveTextContent('Monthly payment')
  })

  test('renders the amount', () => {
    renderPaymentSummary()

    const amountEl = screen.queryByTestId('billable-amount')
    expect(amountEl).toBeInTheDocument()

    expect(amountEl).toHaveTextContent('$100.00')
  })

  test('renders the amount description for metered bundled', () => {
    const billableLicenses = 100
    const billingTermEndDate = 'January 30, 2025'
    renderPaymentSummary({billableLicenses, billingTermEndDate})

    const titleEl = screen.queryByTestId('billable-amount-description')
    expect(titleEl).toBeInTheDocument()

    const expectedTitle = `Amount based on ${billableLicenses} billable licenses, due by ${billingTermEndDate}.`
    expect(titleEl).toHaveTextContent(expectedTitle)
  })

  test('renders the amount description for volume bundled', () => {
    const billableLicenses = 80
    renderPaymentSummary({billableLicenses, isMeteredLicensed: false})

    const titleEl = screen.queryByTestId('billable-amount-description')
    expect(titleEl).toBeInTheDocument()

    const expectedTitle = `Amount based on ${billableLicenses} purchased licenses.`
    expect(titleEl).toHaveTextContent(expectedTitle)
  })

  test('more details button opens dialog with details', async () => {
    const {user} = renderPaymentSummary({
      billableLicenses: 3,
      currentPayment: '$147.00',
    })

    const buttonEl = screen.getByTestId('more-details-btn')
    expect(buttonEl).toBeInTheDocument()

    await user.click(buttonEl)

    const currentPaymentEl = screen.getByTestId('current-payment')
    expect(currentPaymentEl).toBeInTheDocument()
    expect(currentPaymentEl).toHaveTextContent('$147.00')

    const paymentDescriptionEl = screen.getByTestId('payment-description')
    expect(paymentDescriptionEl).toBeInTheDocument()
    expect(paymentDescriptionEl).toHaveTextContent('Amount based on 3 billable licenses, due by February 27, 2025.')

    const licensesEl = screen.getByTestId('bundled-billable-licenses')
    expect(licensesEl).toBeInTheDocument()
    expect(licensesEl).toHaveTextContent('3 Secret Protection and Code Security licenses')

    const unitPriceEl = screen.getByTestId('bundled-unit-price')
    expect(unitPriceEl).toBeInTheDocument()
    expect(unitPriceEl).toHaveTextContent('$49/month each')

    const billableAmountEl = screen.getByTestId('bundled-billable-amount')
    expect(billableAmountEl).toBeInTheDocument()
    expect(billableAmountEl).toHaveTextContent('$147')

    const viewUsageDetailsEl = screen.getByTestId('view-usage-details-btn')
    expect(viewUsageDetailsEl).toBeInTheDocument()
    expect(viewUsageDetailsEl).toHaveAttribute('href', '/billing/usage?group=2&query=product:ghas')
  })
})

import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {PaymentSummary} from '../PaymentSummary'

const defaultTestProps = {
  title: 'Estimated next payment',
  currentPayment: '$100.00',
  description: 'Amount based on 100 billable licenses, due by January 30, 2025.',
}

const renderPaymentSummary = (overrideProps = {}) => {
  return render(<PaymentSummary {...defaultTestProps} {...overrideProps} />)
}

describe('PaymentSummary Component', () => {
  test('renders the base text elements', () => {
    renderPaymentSummary()

    const titleEl = screen.queryByTestId('payment-summary-title')
    expect(titleEl).toBeInTheDocument()
    expect(titleEl).toHaveTextContent('Estimated next payment')

    const amountEl = screen.queryByTestId('billable-amount')
    expect(amountEl).toBeInTheDocument()
    expect(amountEl).toHaveTextContent('$100.00')

    const descriptionEl = screen.queryByTestId('billable-amount-description')
    expect(descriptionEl).toBeInTheDocument()
    expect(descriptionEl).toHaveTextContent('Amount based on 100 billable licenses, due by January 30, 2025.')
  })

  test('renders more details dialog when dialog content is provided', async () => {
    const {user} = renderPaymentSummary({
      moreDetailsBody: (
        <>
          <div data-testid="current-payment">$147.00</div>
          <div data-testid="payment-description">Amount based on 3 billable licenses, due by February 27, 2025.</div>
          <div data-testid="bundled-billable-licenses">3 Advanced Security licenses</div>
          <div data-testid="bundled-unit-price">$49/month each</div>
          <div data-testid="bundled-billable-amount">$147</div>
        </>
      ),
      moreDetailsButtons: (
        <a data-testid="view-usage-details-btn" href="/billing/usage?group=2&query=product:ghas">
          View usage details
        </a>
      ),
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
    expect(licensesEl).toHaveTextContent('3 Advanced Security licenses')

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

import {render, screen, act} from '@testing-library/react'
import {CopilotPaymentSummary} from '../CopilotPaymentSummary'
import {getCopilotPaymentSummaryProps} from '../../../licensing-common/test-utils/mock-data'

const renderPaymentSummary = (overrideProps = {}) => {
  return render(<CopilotPaymentSummary {...getCopilotPaymentSummaryProps()} {...overrideProps} />)
}
describe('PaymentSummary Component', () => {
  test('renders the payment summary UI elements', () => {
    renderPaymentSummary()

    const paymentSummaryTitleEl = screen.queryByTestId('payment-summary-title')
    expect(paymentSummaryTitleEl).toBeInTheDocument()
    expect(paymentSummaryTitleEl).toHaveTextContent('Estimated next payment')

    const paymentSummaryBillableAmountEl = screen.queryByTestId('billable-amount')
    expect(paymentSummaryBillableAmountEl).toBeInTheDocument()
    expect(paymentSummaryBillableAmountEl).toHaveTextContent('$252.00')

    const paymentSummaryDescEl = screen.queryByTestId('billable-amount-description')
    expect(paymentSummaryDescEl).toBeInTheDocument()
    expect(paymentSummaryDescEl).toHaveTextContent('Amount based on 8 billable licenses, due by January 20, 2025.')

    const paymentSummaryDetailsButtonEl = screen.queryByTestId('payment-summary-details-button')
    expect(paymentSummaryDetailsButtonEl).toBeInTheDocument()
    expect(paymentSummaryDetailsButtonEl).toHaveTextContent('More details')
  })

  test('formats the total cost correctly', () => {
    renderPaymentSummary({totalCost: 207261})
    const paymentSummaryBillableAmountEl = screen.queryByTestId('billable-amount')
    expect(paymentSummaryBillableAmountEl).toHaveTextContent('$207,261.00')
  })

  test('opens the payment summary details dialog when "More details" is clicked', () => {
    renderPaymentSummary()

    const paymentSummaryDetailsButtonEl = screen.queryByTestId('payment-summary-details-button')
    if (paymentSummaryDetailsButtonEl) {
      act(() => {
        paymentSummaryDetailsButtonEl.click()
      })
    }
    expect(screen.getByRole('dialog')).toBeInTheDocument()
  })

  test('renders the payment summary details dialog', () => {
    renderPaymentSummary()
    const paymentSummaryDetailsButtonEl = screen.queryByTestId('payment-summary-details-button')
    if (paymentSummaryDetailsButtonEl) {
      act(() => {
        paymentSummaryDetailsButtonEl.click()
      })
    }
    const paymentSummaryDetailsEl = screen.getByRole('dialog')
    expect(paymentSummaryDetailsEl).toBeInTheDocument()
    expect(paymentSummaryDetailsEl).toHaveTextContent('Estimated next payment')
    expect(paymentSummaryDetailsEl).toHaveTextContent('$252.00')
    expect(paymentSummaryDetailsEl).toHaveTextContent('Amount based on 8 billable licenses, due by January 20, 2025.')
    expect(paymentSummaryDetailsEl).toHaveTextContent('3 Copilot Business licenses')
    expect(paymentSummaryDetailsEl).toHaveTextContent('$19.00/month each')
    expect(paymentSummaryDetailsEl).toHaveTextContent('$57.00')
    expect(paymentSummaryDetailsEl).toHaveTextContent('5 Copilot Enterprise licenses')
    expect(paymentSummaryDetailsEl).toHaveTextContent('$39.00/month each')
    expect(paymentSummaryDetailsEl).toHaveTextContent('$195.00')
    expect(paymentSummaryDetailsEl).toHaveTextContent('View billing details')
    expect(paymentSummaryDetailsEl).toHaveTextContent('Done')
  })

  test('renders and calculates the payment summary details dialog with larger values', () => {
    renderPaymentSummary({
      billingTermEndDate: 'December 31, 2025',
      totalCost: 207261,
      skus: [
        {sku: 'business', unitPrice: 19, consumedLicenses: 399},
        {sku: 'enterprise', unitPrice: 39, consumedLicenses: 5120},
      ],
    })
    const paymentSummaryDetailsButtonEl = screen.queryByTestId('payment-summary-details-button')
    if (paymentSummaryDetailsButtonEl) {
      act(() => {
        paymentSummaryDetailsButtonEl.click()
      })
    }
    const paymentSummaryDetailsEl = screen.getByRole('dialog')
    expect(paymentSummaryDetailsEl).toBeInTheDocument()
    expect(paymentSummaryDetailsEl).toHaveTextContent('Estimated next payment')
    expect(paymentSummaryDetailsEl).toHaveTextContent('$207,261.00')
    expect(paymentSummaryDetailsEl).toHaveTextContent(
      'Amount based on 5,519 billable licenses, due by December 31, 2025.',
    )
    expect(paymentSummaryDetailsEl).toHaveTextContent('399 Copilot Business licenses')
    expect(paymentSummaryDetailsEl).toHaveTextContent('$19.00/month each')
    expect(paymentSummaryDetailsEl).toHaveTextContent('$7,581.00')
    expect(paymentSummaryDetailsEl).toHaveTextContent('5120 Copilot Enterprise licenses')
    expect(paymentSummaryDetailsEl).toHaveTextContent('$39.00/month each')
    expect(paymentSummaryDetailsEl).toHaveTextContent('$199,680.00')
    expect(paymentSummaryDetailsEl).toHaveTextContent('View billing details')
    expect(paymentSummaryDetailsEl).toHaveTextContent('Done')
  })

  test('closes the payment summary details dialog when "Done" is clicked', () => {
    renderPaymentSummary()

    const paymentSummaryDetailsButtonEl = screen.queryByTestId('payment-summary-details-button')
    if (paymentSummaryDetailsButtonEl) {
      act(() => {
        paymentSummaryDetailsButtonEl.click()
      })
    }
    const closeButtonEl = screen.getByTestId('done-button')
    if (closeButtonEl) {
      act(() => {
        closeButtonEl.click()
      })
    }
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })
})

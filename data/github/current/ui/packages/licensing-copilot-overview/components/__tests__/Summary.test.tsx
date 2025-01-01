import {getSummaryProps} from '../../test-utils/mock-data'
import {render, screen} from '@testing-library/react'
import {NavigationContextProvider} from '@github-ui/licensing-common/contexts/NavigationContext'
import {Summary} from '../Summary'

const renderSummary = (overrideProps = {}) => {
  return render(
    <NavigationContextProvider enterpriseContactUrl={'/enterprise-contact-url'} isStafftools={false} slug={'test-co'}>
      <Summary {...getSummaryProps()} {...overrideProps} />
    </NavigationContextProvider>,
  )
}

describe('Summary Component', () => {
  test('renders the CTA UI when isCopilotEnabled is false', () => {
    renderSummary({isCopilotEnabled: false})

    const enableCopilotCtaEl = screen.queryByTestId('enable-copilot-cta')
    expect(enableCopilotCtaEl).toBeInTheDocument()
  })

  test('renders message when isCopilotEnabled is false and isStafftools is true', () => {
    render(
      <NavigationContextProvider enterpriseContactUrl={'/enterprise-contact-url'} isStafftools slug={'test-co'}>
        <Summary {...getSummaryProps()} isCopilotEnabled={false} />
      </NavigationContextProvider>,
    )

    const stafftoolsCopilotDisabledEl = screen.queryByTestId('stafftools-copilot-disabled')
    expect(stafftoolsCopilotDisabledEl).toBeInTheDocument()
  })

  test('render the summary UI when isCopilotEnabled is false', () => {
    renderSummary({isCopilotEnabled: true})

    const enableCopilotCtaEl = screen.queryByTestId('enable-copilot-cta')
    expect(enableCopilotCtaEl).not.toBeInTheDocument()
    const usagePaymentSummaryEl = screen.queryByTestId('usage-payment-summary')
    expect(usagePaymentSummaryEl).toBeInTheDocument()
    const usageSummaryHeaderEl = screen.queryByTestId('usage-summary-header-title')
    expect(usageSummaryHeaderEl).toBeInTheDocument()
    expect(usageSummaryHeaderEl).toHaveTextContent('Consumed licenses')
    const usageSummaryItemAmountsEl = screen.queryAllByTestId('summary-item-amount')
    expect(usageSummaryItemAmountsEl).toHaveLength(2)
    expect(usageSummaryItemAmountsEl[0]).toHaveTextContent('3')
    expect(usageSummaryItemAmountsEl[1]).toHaveTextContent('5')
    const usageSummaryItemDescEl = screen.queryAllByTestId('summary-amount-desc')
    expect(usageSummaryItemDescEl).toHaveLength(2)
    expect(usageSummaryItemDescEl[0]).toHaveTextContent('Business licenses')
    expect(usageSummaryItemDescEl[1]).toHaveTextContent('Enterprise licenses')
    const paymentSummaryTitleEl = screen.queryByTestId('payment-summary-title')
    expect(paymentSummaryTitleEl).toBeInTheDocument()
    expect(paymentSummaryTitleEl).toHaveTextContent('Estimated next payment')
    const paymentSummaryBillableAmountEl = screen.queryByTestId('billable-amount')
    expect(paymentSummaryBillableAmountEl).toBeInTheDocument()
    expect(paymentSummaryBillableAmountEl).toHaveTextContent('$252.00')
  })
})

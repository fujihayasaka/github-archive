import {getSummaryProps} from '../../test-utils/mock-data'
import {act, render, screen} from '@testing-library/react'
import {NavigationContextProvider} from '@github-ui/licensing-common/contexts/NavigationContext'
import {Summary} from '../Summary'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {MemoryRouter} from 'react-router-dom'

const renderSummary = (overrideProps = {}) => {
  return render(
    <MemoryRouter future={{v7_relativeSplatPath: true, v7_startTransition: true}}>
      <NavigationContextProvider
        enterpriseContactUrl={'/enterprise-contact-url'}
        isTeams={false}
        isStafftools={false}
        slug={'test-co'}
      >
        <Summary {...getSummaryProps()} {...overrideProps} />
      </NavigationContextProvider>
    </MemoryRouter>,
  )
}

const mockVerifiedFetch = verifiedFetch as jest.Mock
// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetch: jest.fn(),
}))

describe('Summary Component', () => {
  test('renders the CTA UI when isCopilotEnabled is false', () => {
    renderSummary({isCopilotEnabled: false})

    const enableCopilotCtaEl = screen.queryByTestId('enable-copilot-cta')
    expect(enableCopilotCtaEl).toBeInTheDocument()
  })

  test('renders message when isCopilotEnabled is false and isStafftools is true', () => {
    render(
      <MemoryRouter future={{v7_relativeSplatPath: true, v7_startTransition: true}}>
        <NavigationContextProvider
          isTeams={false}
          enterpriseContactUrl={'/enterprise-contact-url'}
          isStafftools
          slug={'test-co'}
        >
          <Summary {...getSummaryProps()} isCopilotEnabled={false} />
        </NavigationContextProvider>
      </MemoryRouter>,
    )

    const stafftoolsCopilotDisabledEl = screen.queryByTestId('stafftools-copilot-disabled')
    expect(stafftoolsCopilotDisabledEl).toBeInTheDocument()
  })

  test('render the summary UI when isCopilotEnabled is true', () => {
    renderSummary({isCopilotEnabled: true, copilotCanBeReenabled: false})

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
    const warningMessage = screen.queryByText('Copilot access has been disabled for the entire enterprise')
    expect(warningMessage).not.toBeInTheDocument()
  })

  test('when copilotCanBeReenabled is true, render a button to re-enable copilot, a warning banner that copilot has been disabled, and the EnableCTA element', () => {
    renderSummary({isCopilotEnabled: false, copilotCanBeReenabled: true})

    const warningMessage = screen.queryByText('Copilot access has been disabled for the entire enterprise')
    expect(warningMessage).toBeInTheDocument()

    const reenableCopilotCta = screen.queryByTestId('reenable-copilot-button')
    expect(reenableCopilotCta).toBeInTheDocument()
    const enableCopilotCtaEl = screen.queryByTestId('enable-copilot-cta')
    expect(enableCopilotCtaEl).toBeInTheDocument()
  })

  test('handles CSV export', async () => {
    mockVerifiedFetch.mockResolvedValue({
      ok: true,
      status: 200,
    })

    renderSummary({isCopilotEnabled: true})
    const downloadCsvButtonEl = screen.getByTestId('download-csv-button')
    await act(async () => downloadCsvButtonEl.click())
    expect(mockVerifiedFetch).toHaveBeenCalledWith('/enterprises/test-co/settings/download_seat_management_usage', {
      method: 'GET',
      headers: {
        Accept: 'text/csv',
      },
    })
  })

  test('CSV export displays an error message if the download fails', async () => {
    mockVerifiedFetch.mockResolvedValue({
      ok: false,
      statusText: 'BAD REQUEST',
      status: 400,
    })

    renderSummary({isCopilotEnabled: true})
    expect(screen.queryByTestId('csv-download-error-banner')).not.toBeInTheDocument()
    const downloadCsvButtonEl = screen.getByTestId('download-csv-button')
    await act(async () => downloadCsvButtonEl.click())
    expect(screen.getByTestId('csv-download-error-banner')).toBeInTheDocument()
  })

  test('error message is displayed if copilot enablement fails', async () => {
    mockVerifiedFetch.mockResolvedValue({
      ok: false,
      statusText: 'BAD REQUEST',
      status: 400,
    })

    renderSummary({isCopilotEnabled: false})
    expect(screen.queryByTestId('copilot-enablement-error-banner')).not.toBeInTheDocument()
    const enableCopilotButton = screen.getByTestId('enable-copilot-button')
    await act(async () => enableCopilotButton.click())
    expect(screen.getByTestId('copilot-enablement-error-banner')).toBeInTheDocument()
  })
})

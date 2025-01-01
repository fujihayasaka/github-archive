import {render, screen, act} from '@testing-library/react'
import {getSummaryProps} from '../../test-utils/mock-data'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {SummaryHeaderButtons} from '../../components/SummaryHeaderButtons'

const mockVerifiedFetch = verifiedFetch as jest.Mock
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetch: jest.fn(),
}))

const renderSummaryHeaderButtons = (overrideProps = {}) => {
  return render(<SummaryHeaderButtons isStafftools={false} {...getSummaryProps()} {...overrideProps} />)
}

describe('SummaryHeaderButtons Component', () => {
  test('renders the Enable Copilot button if isCopilotEnabled false', () => {
    renderSummaryHeaderButtons({isCopilotEnabled: false, businessSlug: 'test-co'})
    const enableCopilotButtonEl = screen.queryByTestId('enable-copilot-button')
    expect(enableCopilotButtonEl).toBeInTheDocument()
    expect(enableCopilotButtonEl).toHaveTextContent('Enable Copilot')
    expect(enableCopilotButtonEl).toHaveAttribute('data-variant', 'primary')
  })

  test('does not render the Enable Copilot button if isCopilotEnabled false and isStafftools true', () => {
    render(<SummaryHeaderButtons isStafftools {...getSummaryProps()} isCopilotEnabled={false} />)
    const enableCopilotButtonEl = screen.queryByTestId('enable-copilot-button')
    expect(enableCopilotButtonEl).not.toBeInTheDocument()
  })

  test('handles submit for enabling Copilot', async () => {
    renderSummaryHeaderButtons({isCopilotEnabled: false, businessSlug: 'test-co'})
    mockWindowLocationReload()

    const enableCopilotButtonEl = screen.queryByTestId('enable-copilot-button')
    expect(enableCopilotButtonEl).toBeInTheDocument()
    if (enableCopilotButtonEl) {
      await act(async () => enableCopilotButtonEl.click())
    }

    const expectedFormData = new FormData()
    expectedFormData.append('copilot_enabled', 'selected_organizations')
    expect(mockVerifiedFetch).toHaveBeenCalledWith('/enterprises/test-co/settings/update_copilot_enablement', {
      method: 'PUT',
      body: expectedFormData,
    })
    expect(window.location.reload).toHaveBeenCalled()
  })

  test('renders the Manage and Download CSV buttons if isCopilotEnabled true', () => {
    renderSummaryHeaderButtons({isCopilotEnabled: true, businessSlug: 'test-co'})
    const manageButtonEl = screen.queryByTestId('manage-copilot-button')
    expect(manageButtonEl).toBeInTheDocument()
    expect(manageButtonEl).toHaveTextContent('Manage')
    expect(manageButtonEl).toHaveAttribute('href', '/enterprises/test-co/enterprise_licensing/copilot')
    expect(manageButtonEl).toHaveAttribute('data-variant', 'default')

    const downloadCsvButtonEl = screen.queryByTestId('download-csv-button')
    expect(downloadCsvButtonEl).toBeInTheDocument()
    expect(downloadCsvButtonEl).toHaveTextContent('Download CSV Report')
  })
})

function mockWindowLocationReload() {
  Object.defineProperty(window, 'location', {
    writable: true,
    value: {
      reload: jest.fn(),
    },
  })
}

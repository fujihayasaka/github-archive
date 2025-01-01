import {render, screen, act} from '@testing-library/react'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {CopilotLicensingHeader} from '../CopilotLicensingHeader'
import {NavigationContextProvider} from '@github-ui/licensing-common/contexts/NavigationContext'

const mockVerifiedFetch = verifiedFetch as jest.Mock
// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetch: jest.fn(),
}))

const renderCopilotLicensingHeader = (overrideProps = {}) => {
  return render(
    <NavigationContextProvider enterpriseContactUrl="" isStafftools={false} slug={'test-co'} isTeams={false}>
      <CopilotLicensingHeader {...overrideProps} />
    </NavigationContextProvider>,
  )
}

describe('CopilotLicensingHeader Component', () => {
  test('renders the CopilotLicensingHeader component, with the Export CSV and policies buttons', async () => {
    renderCopilotLicensingHeader()
    expect(screen.getByTestId('licensing-copilot-header')).toBeInTheDocument()
    expect(screen.getByTestId('download-csv-button')).toBeInTheDocument()

    const policiesButton = screen.getByRole('link', {name: /View Policies/i})
    expect(policiesButton).toBeInTheDocument()
    expect(policiesButton).toHaveAttribute('href', '/enterprises/test-co/settings/copilot?tab=policies')
  })

  test('handles CSV export', async () => {
    renderCopilotLicensingHeader()

    const exportCsvButton = screen.getByTestId('download-csv-button')
    expect(exportCsvButton).toBeInTheDocument()
    await act(async () => exportCsvButton.click())

    expect(mockVerifiedFetch).toHaveBeenCalledWith('/enterprises/test-co/settings/download_seat_management_usage', {
      method: 'GET',
      headers: {
        Accept: 'text/csv',
      },
    })
  })

  test('shows an error banner if the download is not successful', async () => {
    mockVerifiedFetch.mockResolvedValue({
      ok: false,
      statusText: 'BAD REQUEST',
      status: 400,
    })

    renderCopilotLicensingHeader()

    expect(screen.queryByTestId('csv-download-error-banner')).not.toBeInTheDocument()
    const exportCsvButton = screen.getByTestId('download-csv-button')
    expect(exportCsvButton).toBeInTheDocument()
    await act(async () => exportCsvButton.click())

    expect(mockVerifiedFetch).toHaveBeenCalledWith('/enterprises/test-co/settings/download_seat_management_usage', {
      method: 'GET',
      headers: {
        Accept: 'text/csv',
      },
    })

    expect(screen.getByTestId('csv-download-error-banner')).toBeInTheDocument()
  })
})

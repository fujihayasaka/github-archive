import {render, screen, act} from '@testing-library/react'
import {getSummaryProps} from '../../test-utils/mock-data'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {SummaryHeaderButtons} from '../../components/SummaryHeaderButtons'
import {MemoryRouter} from 'react-router-dom'
import {NavigationContextProvider} from '@github-ui/licensing-common/contexts/NavigationContext'

const mockVerifiedFetch = verifiedFetch as jest.Mock
// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetch: jest.fn(),
}))

const navigateFn = jest.fn()
jest.mock('@github-ui/use-navigate', () => {
  return {
    useNavigate: () => navigateFn,
  }
})

const onEnablementErrorMock = jest.fn()

const renderSummaryHeaderButtons = (overrideProps = {}) => {
  return render(
    <MemoryRouter future={{v7_relativeSplatPath: true, v7_startTransition: true}}>
      <NavigationContextProvider enterpriseContactUrl="" isTeams={false} isStafftools={false} slug={'test-co'}>
        <SummaryHeaderButtons
          isStafftools={false}
          onDownloadError={jest.fn()}
          onEnablementError={onEnablementErrorMock}
          {...getSummaryProps()}
          {...overrideProps}
        />
      </NavigationContextProvider>
    </MemoryRouter>,
  )
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
    render(
      <MemoryRouter future={{v7_relativeSplatPath: true, v7_startTransition: true}}>
        <SummaryHeaderButtons
          isStafftools
          onDownloadError={jest.fn()}
          {...getSummaryProps()}
          isCopilotEnabled={false}
          onEnablementError={jest.fn()}
        />
      </MemoryRouter>,
    )
    const enableCopilotButtonEl = screen.queryByTestId('enable-copilot-button')
    expect(enableCopilotButtonEl).not.toBeInTheDocument()
  })

  test('handles submit for enabling Copilot, and redirects to the licensing subpage', async () => {
    mockVerifiedFetch.mockResolvedValue({ok: true})
    renderSummaryHeaderButtons({isCopilotEnabled: false, businessSlug: 'test-co'})

    const enableCopilotButtonEl = screen.queryByTestId('enable-copilot-button')
    expect(enableCopilotButtonEl).toBeInTheDocument()
    if (enableCopilotButtonEl) {
      await act(async () => enableCopilotButtonEl.click())
    }

    const expectedFormData = new FormData()
    expectedFormData.append('copilot_enabled', 'selected_organizations')
    expect(mockVerifiedFetch).toHaveBeenCalledWith(`/enterprises/test-co/settings/update_copilot_enablement`, {
      method: 'PUT',
      body: expectedFormData,
    })
    expect(navigateFn).toHaveBeenCalledWith('/enterprises/test-co/enterprise_licensing/copilot')
  })

  test('if enabling Copilot fails, runs onEnablementError logic', async () => {
    mockVerifiedFetch.mockResolvedValue({ok: false})
    renderSummaryHeaderButtons({isCopilotEnabled: false, businessSlug: 'test-co'})

    const enableCopilotButtonEl = screen.queryByTestId('enable-copilot-button')
    expect(enableCopilotButtonEl).toBeInTheDocument()
    if (enableCopilotButtonEl) {
      await act(async () => enableCopilotButtonEl.click())
    }

    const expectedFormData = new FormData()
    expectedFormData.append('copilot_enabled', 'selected_organizations')
    expect(mockVerifiedFetch).toHaveBeenCalledWith(`/enterprises/test-co/settings/update_copilot_enablement`, {
      method: 'PUT',
      body: expectedFormData,
    })
    expect(onEnablementErrorMock).toHaveBeenCalled()
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
    expect(downloadCsvButtonEl).toHaveTextContent('CSV Report')
  })

  test('renders the re-enable copilot and Download CSV buttons if copilotCanBeReenabled is true, and hides the Manage and Enable copilot buttons', () => {
    renderSummaryHeaderButtons({isCopilotEnabled: false, copilotCanBeReenabled: true, businessSlug: 'test-co'})
    const reenableCopilotButton = screen.queryByTestId('reenable-copilot-button')
    expect(reenableCopilotButton).toBeInTheDocument()
    expect(reenableCopilotButton).toHaveTextContent('Re-enable Copilot')
    expect(reenableCopilotButton).toHaveAttribute('data-variant', 'primary')

    const downloadCsvButtonEl = screen.queryByTestId('download-csv-button')
    expect(downloadCsvButtonEl).toBeInTheDocument()
    expect(downloadCsvButtonEl).toHaveTextContent('CSV Report')

    expect(screen.queryByTestId('manage-copilot-button')).not.toBeInTheDocument()
    expect(screen.queryByTestId('enable-copilot-button')).not.toBeInTheDocument()
  })

  test('does not render the re-enable copilot button if copilotCanBeReenabled is false', () => {
    renderSummaryHeaderButtons({isCopilotEnabled: true, copilotCanBeReenabled: false, businessSlug: 'test-co'})
    expect(screen.queryByTestId('reenable-copilot-button')).not.toBeInTheDocument()
  })

  test('handles submit for re-enable copilot button', async () => {
    renderSummaryHeaderButtons({isCopilotEnabled: false, copilotCanBeReenabled: true, businessSlug: 'test-co'})
    const reenableCopilotButton = screen.queryByTestId('reenable-copilot-button')
    expect(reenableCopilotButton).toBeInTheDocument()
    if (reenableCopilotButton) {
      await act(async () => reenableCopilotButton.click())
    }

    const expectedFormData = new FormData()
    expectedFormData.append('copilot_enabled', 'selected_organizations')
    expect(mockVerifiedFetch).toHaveBeenCalledWith(`/enterprises/test-co/settings/update_copilot_enablement`, {
      method: 'PUT',
      body: expectedFormData,
    })
  })
})

import {render, screen, act} from '@testing-library/react'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {CopilotOrganizationGeneralAccessDropdown} from '../../organizations/CopilotOrganizationGeneralAccessDropdown'
import {NavigationContextProvider} from '@github-ui/licensing-common/contexts/NavigationContext'
import {ThemeProvider} from '@primer/react'
import {MemoryRouter} from 'react-router-dom'

const mockVerifiedFetch = verifiedFetch as jest.Mock
// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetch: jest.fn().mockResolvedValue({ok: true}),
}))
const navigateFn = jest.fn()
jest.mock('@github-ui/use-navigate', () => {
  return {
    useNavigate: () => navigateFn,
  }
})

const renderCopilotOrganizationGeneralAccessDropdown = () => {
  return render(
    <MemoryRouter future={{v7_relativeSplatPath: true, v7_startTransition: true}}>
      <ThemeProvider>
        <NavigationContextProvider
          enterpriseContactUrl={'/enterprise-contact-url'}
          isStafftools={false}
          isTeams={false}
          slug={'test-co'}
        >
          <CopilotOrganizationGeneralAccessDropdown enablementSetting={'selected_organizations'} />
        </NavigationContextProvider>
      </ThemeProvider>
      ,
    </MemoryRouter>,
  )
}

describe('CopilotOrganizationGeneralAccessDropdown Component', () => {
  test('renders the CopilotOrganizationGeneralAccessDropdown component', async () => {
    renderCopilotOrganizationGeneralAccessDropdown()
    const copilotAccessSection = screen.queryByTestId('licensing-copilot-access-org-enablement')
    expect(copilotAccessSection).toBeInTheDocument()

    const dropdownButton = screen.getByRole('button', {name: /specific organizations/i})
    expect(dropdownButton).toBeInTheDocument()
    if (dropdownButton) {
      await act(async () => dropdownButton.click())
    }

    const enableForAllOption = screen.getByTestId('org-item-all-organizations')
    const enableForSelectedOption = screen.getByTestId('org-item-selected-organizations')
    const disableOption = screen.getByTestId('org-item-disabled')
    expect(enableForAllOption).toBeInTheDocument()
    expect(enableForSelectedOption).toBeInTheDocument()
    expect(disableOption).toBeInTheDocument()
  })

  test('handles submit for changing Copilot enablement value', async () => {
    renderCopilotOrganizationGeneralAccessDropdown()

    const dropdownButton = screen.getByRole('button', {name: /specific organizations/i})
    expect(dropdownButton).toBeInTheDocument()
    if (dropdownButton) {
      await act(async () => dropdownButton.click())
    }

    const disableOption = screen.getByTestId('org-item-disabled')
    expect(disableOption).toBeInTheDocument()
    if (disableOption) {
      await act(async () => disableOption.click())
    }

    const expectedFormData = new FormData()
    expectedFormData.append('copilot_enabled', 'disabled')
    expect(mockVerifiedFetch).toHaveBeenCalledWith('/enterprises/test-co/settings/update_copilot_enablement', {
      method: 'PUT',
      body: expectedFormData,
    })

    expect(navigateFn).toHaveBeenCalledWith('/enterprises/test-co/enterprise_licensing/copilot')
  })
})

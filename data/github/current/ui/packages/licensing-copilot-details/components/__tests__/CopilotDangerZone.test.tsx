import {render, screen, act} from '@testing-library/react'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {CopilotDangerZone} from '../CopilotDangerZone'
import {ThemeProvider} from '@primer/react'
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

const renderCopilotDangerZone = (overrideProps = {}) => {
  return render(
    <MemoryRouter future={{v7_relativeSplatPath: true, v7_startTransition: true}}>
      <ThemeProvider>
        <NavigationContextProvider enterpriseContactUrl="" isTeams={false} isStafftools={false} slug={'test-co'}>
          <CopilotDangerZone {...overrideProps} />
        </NavigationContextProvider>
      </ThemeProvider>
      ,
    </MemoryRouter>,
  )
}

describe('CopilotDangerZone Component', () => {
  test('renders the CopilotDangerZone component, and associated dialog when the disable button is clicked', async () => {
    renderCopilotDangerZone()
    expect(screen.getByTestId('licensing-copilot-danger-zone')).toBeInTheDocument()

    const disableButton = screen.getByRole('button', {name: /Disable/i})
    expect(disableButton).toBeInTheDocument()

    await act(async () => disableButton.click())
    const dialogConfirmationButton = screen.getByRole('button', {name: /Disable Copilot/i})
    expect(screen.getByTestId('copilot-danger-zone-dialog')).toBeInTheDocument()
    expect(dialogConfirmationButton).toBeInTheDocument()
  })

  test('handles submit for disabling Copilot', async () => {
    renderCopilotDangerZone()
    const disableButton = screen.getByRole('button', {name: /Disable/i})
    await act(async () => disableButton.click())

    const confirmationButton = screen.getByRole('button', {name: /Disable Copilot/i})
    expect(confirmationButton).toBeInTheDocument()
    await act(async () => confirmationButton.click())

    const expectedFormData = new FormData()
    expectedFormData.append('copilot_enabled', 'disabled')
    expect(mockVerifiedFetch).toHaveBeenCalledWith('/enterprises/test-co/settings/update_copilot_enablement', {
      method: 'PUT',
      body: expectedFormData,
    })
    expect(navigateFn).toHaveBeenCalledWith('/enterprises/test-co/enterprise_licensing')
  })
})

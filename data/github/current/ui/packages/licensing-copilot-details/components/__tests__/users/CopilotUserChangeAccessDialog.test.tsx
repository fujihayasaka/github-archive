import {render, screen, act} from '@testing-library/react'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {NavigationContextProvider} from '@github-ui/licensing-common/contexts/NavigationContext'
import {ThemeProvider} from '@primer/react'
import {CopilotUserChangeAccessDialog} from '../../users/CopilotUserChangeAccessDialog'
import {MemoryRouter} from 'react-router-dom'
import {usersWithCopilotAccess} from '../../../test-utils/mock-data'

const mockVerifiedFetch = verifiedFetch as jest.Mock
// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetch: jest.fn().mockResolvedValue({ok: true}),
}))

afterEach(() => {
  jest.clearAllMocks()
})

const users = usersWithCopilotAccess
const userIds = users.map(user => user.id)

const [firstUser, secondUser] = users
if (!firstUser || !secondUser) {
  throw new Error('Users not found.')
}

const renderCopilotUserChangeAccessConfirmationDialog = (usersList = userIds, isDowngrade = true) => {
  return render(
    <MemoryRouter future={{v7_relativeSplatPath: true, v7_startTransition: true}}>
      <ThemeProvider>
        <NavigationContextProvider
          enterpriseContactUrl={'/enterprise-contact-url'}
          isTeams={false}
          isStafftools={false}
          slug={'test-co'}
        >
          <CopilotUserChangeAccessDialog users={usersList} downgrade={isDowngrade} onClose={jest.fn()} />
        </NavigationContextProvider>
      </ThemeProvider>
    </MemoryRouter>,
  )
}

describe('CopilotUserChangeAccessDialog Component', () => {
  test('renders the CopilotUserChangeAccessDialog component', async () => {
    renderCopilotUserChangeAccessConfirmationDialog()
    expect(screen.getByTestId('copilot-license-change-dialog')).toBeInTheDocument()
  })

  test('handles submit for removing a Copilot license', async () => {
    const testUsers = [firstUser.id]
    renderCopilotUserChangeAccessConfirmationDialog(testUsers)

    const removeLicenseButton = screen.getByRole('button', {name: /Remove licenses/i})
    expect(removeLicenseButton).toBeInTheDocument()
    await act(async () => removeLicenseButton.click())

    const expectedFormData = new FormData()
    expectedFormData.append('users[]', firstUser.id.toString())
    expect(mockVerifiedFetch).toHaveBeenCalledWith('/enterprises/test-co/enterprise_licensing/unassign_user_licenses', {
      method: 'DELETE',
      body: expectedFormData,
    })
  })

  test('handles error on submit for removing a Copilot license', async () => {
    mockVerifiedFetch.mockResolvedValueOnce({ok: false})

    const testUsers = [firstUser.id]
    renderCopilotUserChangeAccessConfirmationDialog(testUsers)

    const removeLicenseButton = screen.getByRole('button', {name: /Remove licenses/i})
    expect(removeLicenseButton).toBeInTheDocument()
    await act(async () => removeLicenseButton.click())

    const expectedFormData = new FormData()
    expectedFormData.append('users[]', firstUser.id.toString())
    expect(mockVerifiedFetch).toHaveBeenCalledWith('/enterprises/test-co/enterprise_licensing/unassign_user_licenses', {
      method: 'DELETE',
      body: expectedFormData,
    })
    expect(screen.getByTestId('copilot-license-change-error-banner')).toBeInTheDocument()
  })

  test('handles submit for bulk removing Copilot licenses for selected members', async () => {
    renderCopilotUserChangeAccessConfirmationDialog()

    const removeLicenseButton = screen.getByRole('button', {name: /Remove licenses/i})
    expect(removeLicenseButton).toBeInTheDocument()
    await act(async () => removeLicenseButton.click())

    const expectedFormData = new FormData()
    expectedFormData.append('users[]', firstUser.id.toString())
    expectedFormData.append('users[]', secondUser.id.toString())

    expect(mockVerifiedFetch).toHaveBeenCalledWith('/enterprises/test-co/enterprise_licensing/unassign_user_licenses', {
      method: 'DELETE',
      body: expectedFormData,
    })
  })

  test('handles submit for adding a Copilot license for a user', async () => {
    const testUsers = [firstUser.id]
    renderCopilotUserChangeAccessConfirmationDialog(testUsers, false) // Set the downgrade flag to false

    const addLicenseButton = screen.getByRole('button', {name: /Add licenses/i})
    expect(addLicenseButton).toBeInTheDocument()
    await act(async () => addLicenseButton.click())

    const expectedFormData = new FormData()
    expectedFormData.append('users[]', firstUser.id.toString())

    expect(mockVerifiedFetch).toHaveBeenNthCalledWith(
      1,
      '/enterprises/test-co/enterprise_licensing/assign_user_licenses',
      {
        method: 'POST',
        body: expectedFormData,
      },
    )
  })

  test('handles submit for adding a Copilot license for multiple users', async () => {
    const testUsers = [firstUser.id, secondUser.id]
    renderCopilotUserChangeAccessConfirmationDialog(testUsers, false)

    const addLicenseButton = screen.getByRole('button', {name: /Add licenses/i})
    expect(addLicenseButton).toBeInTheDocument()
    await act(async () => addLicenseButton.click())

    const expectedFormData = new FormData()
    expectedFormData.append('users[]', firstUser.id.toString())
    expectedFormData.append('users[]', secondUser.id.toString())

    expect(mockVerifiedFetch).toHaveBeenNthCalledWith(
      1,
      '/enterprises/test-co/enterprise_licensing/assign_user_licenses',
      {
        method: 'POST',
        body: expectedFormData,
      },
    )
  })

  test('displays an error message when a Copilot license cannot be assigned', async () => {
    mockVerifiedFetch.mockResolvedValue({
      ok: false,
    })

    const testUsers = [firstUser.id, secondUser.id]
    renderCopilotUserChangeAccessConfirmationDialog(testUsers, false)

    const addLicenseButton = screen.getByRole('button', {name: /Add licenses/i})
    expect(addLicenseButton).toBeInTheDocument()
    await act(async () => addLicenseButton.click())

    const expectedFormData = new FormData()
    expectedFormData.append('users[]', firstUser.id.toString())
    expectedFormData.append('users[]', secondUser.id.toString())

    expect(mockVerifiedFetch).toHaveBeenNthCalledWith(
      1,
      '/enterprises/test-co/enterprise_licensing/assign_user_licenses',
      {
        method: 'POST',
        body: expectedFormData,
      },
    )

    expect(screen.getByTestId('copilot-license-change-error-banner')).toBeInTheDocument()
  })
})

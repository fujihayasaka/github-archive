import {act, render, screen, within} from '@testing-library/react'
import {MemoryRouter} from 'react-router-dom'
import {NavigationContextProvider} from '@github-ui/licensing-common/contexts/NavigationContext'
import {userLicenses, usersWithCopilotAccess} from '../../../test-utils/mock-data'
import {ThemeProvider} from '@primer/react'
import {CopilotUserLicenseSummaryDialog} from '../../users/CopilotUserLicenseSummaryDialog'

const licenses = userLicenses
const user = usersWithCopilotAccess[0]
const dominantLicense = licenses[0]
if (!dominantLicense) {
  throw new Error('license array cannot be empty.')
}
if (!user) {
  throw new Error('User not found.')
}

const renderCopilotUserLicenseSummaryDialog = () => {
  return render(
    <MemoryRouter future={{v7_relativeSplatPath: true, v7_startTransition: true}}>
      <ThemeProvider>
        <NavigationContextProvider
          enterpriseContactUrl={'/enterprise-contact-url'}
          isTeams={false}
          isStafftools={false}
          slug={'test-co'}
        >
          <CopilotUserLicenseSummaryDialog user={user} onClose={jest.fn()} />
        </NavigationContextProvider>
      </ThemeProvider>
    </MemoryRouter>,
  )
}

describe('CopilotUserLicenseSummaryDialog Component', () => {
  test('renders the CopilotUserLicenseSummaryDialog component', () => {
    renderCopilotUserLicenseSummaryDialog()
    expect(screen.getByTestId(`license-assignment-summary-for-${user.id}`)).toBeInTheDocument()
  })

  test('renders all licenses belonging to the user', () => {
    renderCopilotUserLicenseSummaryDialog()
    expect(screen.getByTestId(`license-assignment-summary-for-${user.id}`)).toBeInTheDocument()

    for (const license of licenses) {
      expect(screen.getByTestId(`license-information-for-${license.ownerId}`)).toBeInTheDocument()

      // Check for remove button presence based on owner type
      const removeLicenseButton = screen.queryByTestId(`remove-license-button-${license.ownerId}`)
      const buttonShouldExist = license.ownerType !== 'organization'

      expect(removeLicenseButton !== null).toBe(buttonShouldExist)
    }
  })

  test('renders information on the dominant license for the user', () => {
    renderCopilotUserLicenseSummaryDialog()
    expect(screen.getByTestId(`license-assignment-summary-for-${user.id}`)).toBeInTheDocument()

    expect(screen.getByTestId(`dominant-license-for-${user.id}`)).toBeInTheDocument()
    expect(screen.getByText('Active')).toBeInTheDocument()
    expect(
      within(screen.getByTestId(`dominant-license-for-${user.id}`)).getByText(dominantLicense.ownerName),
    ).toBeInTheDocument()
    expect(
      within(screen.getByTestId(`dominant-license-for-${user.id}`)).getByText(content => {
        const planTypeCapitalized = dominantLicense.planType.charAt(0).toUpperCase() + dominantLicense.planType.slice(1)
        return content.includes(planTypeCapitalized)
      }),
    ).toBeInTheDocument()
  })

  test('displays the status of the dominant license when in a pending cancellation state', () => {
    dominantLicense.expirationDate = '2023-10-01'

    renderCopilotUserLicenseSummaryDialog()
    expect(screen.getByTestId(`license-assignment-summary-for-${user.id}`)).toBeInTheDocument()

    expect(screen.getByTestId(`dominant-license-for-${user.id}`)).toBeInTheDocument()
    expect(screen.getByText('Pending cancellation')).toBeInTheDocument()

    // Can no longer remove the license from the dialog
    const removeLicenseButton = screen.queryByTestId(`remove-license-button-${dominantLicense.ownerId}`)
    expect(removeLicenseButton).not.toBeInTheDocument()
  })

  test('renders the CopilotUserAccessChangeConfirmationDialog to remove a license', async () => {
    renderCopilotUserLicenseSummaryDialog()
    expect(screen.getByTestId(`license-assignment-summary-for-${user.id}`)).toBeInTheDocument()

    if (!licenses[1]) {
      throw new Error('Second license is not defined.')
    }
    const removeLicenseButton = screen.getByTestId(`remove-license-button-${licenses[1].ownerId}`)
    expect(removeLicenseButton).toBeInTheDocument()
    await act(async () => removeLicenseButton.click())

    expect(screen.getByTestId(`copilot-license-change-dialog`)).toBeInTheDocument()
  })
})

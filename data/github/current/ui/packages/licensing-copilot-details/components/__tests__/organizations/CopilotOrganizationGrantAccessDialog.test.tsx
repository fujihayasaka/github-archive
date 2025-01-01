import {render, screen, act} from '@testing-library/react'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {MemoryRouter} from 'react-router-dom'
import {NavigationContextProvider} from '@github-ui/licensing-common/contexts/NavigationContext'
import {organizationsWithoutCopilotAccess} from '../../../test-utils/mock-data'
import {CopilotOrganizationGrantAccessDialog} from '../../organizations/CopilotOrganizationGrantAccessDialog'
import {ThemeProvider} from '@primer/react'
import type {Organization} from '../../../types'

const mockVerifiedFetch = verifiedFetch as jest.Mock
// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetch: jest.fn(),
}))

afterEach(() => {
  jest.clearAllMocks()
})

const organizations = organizationsWithoutCopilotAccess
const [org1, org2, org3] = organizationsWithoutCopilotAccess
if (!org1 || !org2 || !org3) {
  throw new Error('organizations array cannot be empty.')
}

const selectNewCopilotPlan = async (
  organization: Organization,
  copilotPlan: 'business' | 'enterprise' | 'disabled',
) => {
  await act(async () => {
    screen.getByTestId(`org-copilot-plan-dropdown-${organization.login}`).click()
  })

  await act(async () => {
    screen.getByTestId(`org-copilot-plan-${organization.id}-${copilotPlan}`).click()
  })

  screen.getByLabelText(`Select all organizations on this page`).focus()
}

const renderCopilotOrganizationGrantAccessDialog = (orgs?: Organization[]) => {
  return render(
    <MemoryRouter future={{v7_relativeSplatPath: true, v7_startTransition: true}}>
      <ThemeProvider>
        <NavigationContextProvider
          enterpriseContactUrl={'/enterprise-contact-url'}
          isTeams={false}
          isStafftools={false}
          slug={'test-co'}
        >
          <CopilotOrganizationGrantAccessDialog organizations={orgs || organizations} onDialogClose={jest.fn()} />
        </NavigationContextProvider>
      </ThemeProvider>
    </MemoryRouter>,
  )
}

describe('CopilotOrganizationGrantAccessDialog Component', () => {
  test('renders the CopilotOrganizationGrantAccessDialog component', async () => {
    renderCopilotOrganizationGrantAccessDialog()
    expect(screen.getByTestId('licensing-copilot-organization-grant-access-list')).toBeInTheDocument()
  })

  test('renders all organizations that are passed in', () => {
    renderCopilotOrganizationGrantAccessDialog()
    expect(screen.getByTestId('licensing-copilot-organization-grant-access-list')).toBeInTheDocument()

    for (const org of organizations) {
      expect(org.copilotPlan === 'disabled' && org.copilotCanBeReenabled === false).toBeTruthy()
      expect(screen.getByText(org.login)).toBeInTheDocument()
    }
  })

  test('displays a dropdown menu for copilot plans for each org that is selected', async () => {
    renderCopilotOrganizationGrantAccessDialog()

    for (const org of organizations) {
      expect(screen.getByTestId(`org-li-${org.login}`)).toBeInTheDocument()
    }

    await act(async () => {
      screen.getByLabelText(`Select ${org1.login}`).click()
      screen.getByLabelText(`Select ${org2.login}`).click()
    })

    expect(screen.getByTestId(`org-copilot-plan-dropdown-${org1.login}`)).toBeInTheDocument()
    expect(screen.getByTestId(`org-copilot-plan-dropdown-${org2.login}`)).toBeInTheDocument()
    expect(screen.queryByTestId(`org-copilot-plan-dropdown-${org3.login}`)).not.toBeInTheDocument()
  })

  test('displays a dropdown menu for copilot plans for all orgs if the `Select All Organizations` checkbox is selected', async () => {
    renderCopilotOrganizationGrantAccessDialog()

    expect(screen.queryByTestId(`org-copilot-plan-dropdown-${org1.login}`)).not.toBeInTheDocument()
    expect(screen.queryByTestId(`org-copilot-plan-dropdown-${org2.login}`)).not.toBeInTheDocument()
    expect(screen.queryByTestId(`org-copilot-plan-dropdown-${org3.login}`)).not.toBeInTheDocument()

    await act(async () => {
      screen.getByLabelText(`Select all organizations on this page`).click()
    })

    expect(screen.getByTestId(`org-copilot-plan-dropdown-${org1.login}`)).toBeInTheDocument()
    expect(screen.getByTestId(`org-copilot-plan-dropdown-${org2.login}`)).toBeInTheDocument()
    expect(screen.getByTestId(`org-copilot-plan-dropdown-${org3.login}`)).toBeInTheDocument()
  })

  test('handles copilot plan change for multiple orgs on different plans if the grant access button is clicked', async () => {
    // Have to pretend that verified fetch always returns a 200
    // otherwise the first call will go through but the second call
    //  won't work
    mockVerifiedFetch.mockResolvedValue({
      ok: true,
    })

    renderCopilotOrganizationGrantAccessDialog()
    const checkbox = screen.getByLabelText(`Select all organizations on this page`)
    await act(async () => {
      checkbox.click()
    })

    expect(screen.getByTestId(`org-copilot-plan-dropdown-${org1.login}`)).toBeInTheDocument()
    expect(screen.getByTestId(`org-copilot-plan-dropdown-${org2.login}`)).toBeInTheDocument()
    expect(screen.getByTestId(`org-copilot-plan-dropdown-${org3.login}`)).toBeInTheDocument()

    await selectNewCopilotPlan(org1, 'enterprise')
    await selectNewCopilotPlan(org2, 'enterprise')
    await selectNewCopilotPlan(org3, 'business')

    const enablementButton = screen.getByRole('button', {name: /Grant access/i})
    expect(enablementButton).toBeInTheDocument()
    await act(async () => enablementButton.click())

    const enterpriseFormData = new FormData()
    enterpriseFormData.append('enablement', 'enterprise')
    enterpriseFormData.append('organizations[]', org1.id.toString())
    enterpriseFormData.append('organizations[]', org2.id.toString())

    const businessFormData = new FormData()
    businessFormData.append('enablement', 'business')
    businessFormData.append('organizations[]', org3.id.toString())

    expect(mockVerifiedFetch).toHaveBeenCalledTimes(2)
    expect(mockVerifiedFetch).toHaveBeenNthCalledWith(
      1,
      '/enterprises/test-co/settings/update_copilot_bulk_org_enablement',
      {
        method: 'PUT',
        body: businessFormData,
      },
    )
    expect(mockVerifiedFetch).toHaveBeenNthCalledWith(
      2,
      '/enterprises/test-co/settings/update_copilot_bulk_org_enablement',
      {
        method: 'PUT',
        body: enterpriseFormData,
      },
    )
  })

  test('does not change copilot plan for an org if the grant access button is clicked after selecting the disabled org option', async () => {
    renderCopilotOrganizationGrantAccessDialog()

    const enablementButton = screen.getByRole('button', {name: /Grant access/i})

    await act(async () => {
      screen.getByLabelText(`Select ${org1.login}`).click()
    })

    await selectNewCopilotPlan(org1, 'enterprise')
    await selectNewCopilotPlan(org1, 'disabled')

    await act(async () => enablementButton.click())

    expect(mockVerifiedFetch).toHaveBeenCalledTimes(0)
  })

  test('displays an error message if the plan update fails', async () => {
    mockVerifiedFetch.mockResolvedValue({
      ok: false,
    })

    renderCopilotOrganizationGrantAccessDialog()

    const enablementButton = screen.getByRole('button', {name: /Grant access/i})

    await act(async () => {
      screen.getByLabelText(`Select ${org1.login}`).click()
    })

    await selectNewCopilotPlan(org1, 'business')
    await act(async () => enablementButton.click())

    expect(mockVerifiedFetch).toHaveBeenCalledTimes(1)
    expect(screen.getByTestId('copilot-grant-access-error-banner')).toBeInTheDocument()
  })

  test('displays pagination controls when organizations exceed page size of 10', () => {
    const manyOrgs = Array.from({length: 25}, (_, i) => ({
      id: i + 1,
      login: `org-${i + 1}`,
      avatarUrl: `https://github.com/org-${i + 1}.png`,
      orgUrl: `/org-${i + 1}`,
      licenseCount: 0,
      copilotPlan: 'disabled',
      copilotCanBeReenabled: false,
      expirationDate: null,
      newPlan: 'disabled',
    }))

    renderCopilotOrganizationGrantAccessDialog(manyOrgs)

    expect(screen.getByRole('navigation', {name: /Pagination/})).toBeInTheDocument()
    expect(screen.getByLabelText('Page 1')).toBeInTheDocument()
    expect(screen.getByLabelText('Page 2')).toBeInTheDocument()
    expect(screen.getByLabelText('Page 3')).toBeInTheDocument()
  })
})

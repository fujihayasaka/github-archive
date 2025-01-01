import {render, screen, act} from '@testing-library/react'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {NavigationContextProvider} from '@github-ui/licensing-common/contexts/NavigationContext'
import {ThemeProvider} from '@primer/react'
import {organizationsWithCopilotAccess} from '../../../test-utils/mock-data'
import {CopilotOrganizationAccessList} from '../../organizations/CopilotOrganizationAccessList'
import {MemoryRouter} from 'react-router-dom'
import type {Organization} from '../../../types'

const mockVerifiedFetch = verifiedFetch as jest.Mock
// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetch: jest.fn().mockResolvedValue({ok: true}),
}))

const organizations = organizationsWithCopilotAccess
const [firstOrganization, secondOrganization, thirdOrganization] = organizations
if (!firstOrganization || !secondOrganization || !thirdOrganization) {
  throw new Error('Organizations not found.')
}

const renderCopilotOrganizationAccessList = (orgs?: Organization[], noOrgsWithCopilotFlag?: boolean) => {
  return render(
    <MemoryRouter future={{v7_relativeSplatPath: true, v7_startTransition: true}}>
      <ThemeProvider>
        <NavigationContextProvider
          enterpriseContactUrl={'/enterprise-contact-url'}
          isTeams={false}
          isStafftools={false}
          slug={'test-co'}
        >
          <CopilotOrganizationAccessList
            setOpenGrantAccessDialog={jest.fn()}
            organizations={orgs || organizations}
            noOrgsWithCopilot={noOrgsWithCopilotFlag || false}
          />
        </NavigationContextProvider>
      </ThemeProvider>
      ,
    </MemoryRouter>,
  )
}

describe('CopilotOrganizationAccessList Component', () => {
  test('renders the CopilotOrganizationAccessList component', async () => {
    renderCopilotOrganizationAccessList()
    expect(screen.getByTestId('licensing-copilot-organization-access-list-view')).toBeInTheDocument()

    const dropdownButton = screen.getByRole('button', {name: /Copilot: Business/i})
    expect(dropdownButton).toBeInTheDocument()

    if (dropdownButton) {
      await act(async () => dropdownButton.click())
    }

    // Each dropdown option should be rendered
    const copilotBusinessOption = screen.getByTestId(`org-copilot-plan-${firstOrganization.id}-business`)
    const copilotEnterpriseOption = screen.getByTestId(`org-copilot-plan-${firstOrganization.id}-enterprise`)
    const disableOption = screen.getByTestId(`org-copilot-plan-${firstOrganization.id}-disabled`)
    expect(copilotBusinessOption).toBeInTheDocument()
    expect(copilotEnterpriseOption).toBeInTheDocument()
    expect(disableOption).toBeInTheDocument()
  })

  test('renders all organizations that are passed in', () => {
    renderCopilotOrganizationAccessList()
    expect(screen.getByTestId('licensing-copilot-organization-access-list-view')).toBeInTheDocument()

    for (const org of organizations) {
      expect(org.copilotPlan !== 'disabled' || org.copilotCanBeReenabled === true).toBeTruthy()
      expect(screen.getByText(org.login)).toBeInTheDocument()
    }
  })

  test('displays expiration date pill when organization has pending downgrade date', () => {
    // Clone the existing organizations and add expiration date to one of them
    const orgsWithExpiration: Organization[] = [
      {
        ...organizationsWithCopilotAccess[0]!,
        expirationDate: '2025-05-30',
      },
      {
        ...organizationsWithCopilotAccess[1]!,
        expirationDate: null,
      },
    ]

    renderCopilotOrganizationAccessList(orgsWithExpiration)

    expect(screen.getByText('github-1')).toBeInTheDocument()
    expect(screen.getByText('github-2')).toBeInTheDocument()

    const allExpirationPills = screen.queryAllByText('Downgrades on 2025-05-30')
    expect(allExpirationPills).toHaveLength(1)
  })

  test('renders the CopilotOrganizationAccessList component, and associated dialog when a plan downgrade is performed', async () => {
    renderCopilotOrganizationAccessList()
    expect(screen.getByTestId('licensing-copilot-organization-access-list-view')).toBeInTheDocument()

    const dropdownButton = screen.getByRole('button', {name: /Copilot: Business/i})
    expect(dropdownButton).toBeInTheDocument()
    if (dropdownButton) {
      await act(async () => dropdownButton.click())
    }

    const disableOption = screen.getByTestId(`org-copilot-plan-${firstOrganization.id}-disabled`)
    expect(disableOption).toBeInTheDocument()
    if (disableOption) {
      await act(async () => disableOption.click())
    }

    const downgradeConfirmationButton = screen.getByRole('button', {name: /Remove Licenses/i})
    expect(screen.getByTestId('copilot-downgrade-confirm-dialog')).toBeInTheDocument()
    expect(downgradeConfirmationButton).toBeInTheDocument()
  })

  test('handles submit for downgrading Copilot plans', async () => {
    renderCopilotOrganizationAccessList()

    const dropdownButton = screen.getByRole('button', {name: /Copilot: Business/i})
    expect(dropdownButton).toBeInTheDocument()
    if (dropdownButton) {
      await act(async () => dropdownButton.click())
    }

    const disableOption = screen.getByTestId(`org-copilot-plan-${firstOrganization.id}-disabled`)
    expect(disableOption).toBeInTheDocument()
    if (disableOption) {
      await act(async () => disableOption.click())
    }

    const downgradeConfirmationButton = screen.getByRole('button', {name: /Remove Licenses/i})
    expect(downgradeConfirmationButton).toBeInTheDocument()
    await act(async () => downgradeConfirmationButton.click())

    const expectedFormData = new FormData()
    expectedFormData.append('enablement', 'disabled')
    expectedFormData.append('organization_id', firstOrganization.id.toString())
    expect(mockVerifiedFetch).toHaveBeenCalledWith(
      '/enterprises/test-co/settings/update_copilot_individual_org_enablement',
      {
        method: 'PUT',
        body: expectedFormData,
      },
    )
  })

  test('handles error on submit for downgrading Copilot plans', async () => {
    mockVerifiedFetch.mockResolvedValueOnce({ok: false})
    renderCopilotOrganizationAccessList()

    const dropdownButton = screen.getByRole('button', {name: /Copilot: Business/i})
    expect(dropdownButton).toBeInTheDocument()
    if (dropdownButton) {
      await act(async () => dropdownButton.click())
    }

    const disableOption = screen.getByTestId(`org-copilot-plan-${firstOrganization.id}-disabled`)
    expect(disableOption).toBeInTheDocument()
    if (disableOption) {
      await act(async () => disableOption.click())
    }

    const downgradeConfirmationButton = screen.getByRole('button', {name: /Remove Licenses/i})
    expect(downgradeConfirmationButton).toBeInTheDocument()
    await act(async () => downgradeConfirmationButton.click())

    const expectedFormData = new FormData()
    expectedFormData.append('enablement', 'disabled')
    expectedFormData.append('organization_id', firstOrganization.id.toString())
    expect(mockVerifiedFetch).toHaveBeenCalledWith(
      '/enterprises/test-co/settings/update_copilot_individual_org_enablement',
      {
        method: 'PUT',
        body: expectedFormData,
      },
    )
    expect(screen.getByTestId('copilot-plan-change-error-banner')).toBeInTheDocument()
  })

  test('renders the CopilotOrganizationAccessList component, and associated dialog when a plan upgrade is performed', async () => {
    renderCopilotOrganizationAccessList()
    expect(screen.getByTestId('licensing-copilot-organization-access-list-view')).toBeInTheDocument()

    const dropdownButton = screen.getByRole('button', {name: /Copilot: Business/i})
    expect(dropdownButton).toBeInTheDocument()
    if (dropdownButton) {
      await act(async () => dropdownButton.click())
    }

    const copilotEnterpriseButton = screen.getByTestId(`org-copilot-plan-${firstOrganization.id}-enterprise`)
    expect(copilotEnterpriseButton).toBeInTheDocument()
    if (copilotEnterpriseButton) {
      await act(async () => copilotEnterpriseButton.click())
    }

    const upgradeConfirmationButton = screen.getByRole('button', {name: /Upgrade licenses/i})
    expect(screen.getByTestId('copilot-upgrade-confirm-dialog')).toBeInTheDocument()
    expect(upgradeConfirmationButton).toBeInTheDocument()
  })

  test('handles submit for upgrading Copilot plans', async () => {
    renderCopilotOrganizationAccessList()

    const dropdownButton = screen.getByRole('button', {name: /Copilot: Business/i})
    expect(dropdownButton).toBeInTheDocument()
    if (dropdownButton) {
      await act(async () => dropdownButton.click())
    }

    const copilotEnterpriseButton = screen.getByTestId(`org-copilot-plan-${firstOrganization.id}-enterprise`)
    expect(copilotEnterpriseButton).toBeInTheDocument()
    if (copilotEnterpriseButton) {
      await act(async () => copilotEnterpriseButton.click())
    }

    const upgradeConfirmationButton = screen.getByRole('button', {name: /Upgrade licenses/i})
    expect(upgradeConfirmationButton).toBeInTheDocument()
    await act(async () => upgradeConfirmationButton.click())

    const expectedFormData = new FormData()
    expectedFormData.append('enablement', 'enterprise')
    expectedFormData.append('organization_id', firstOrganization.id.toString())
    expect(mockVerifiedFetch).toHaveBeenCalledWith(
      '/enterprises/test-co/settings/update_copilot_individual_org_enablement',
      {
        method: 'PUT',
        body: expectedFormData,
      },
    )
  })

  test('handles error on submit for upgrading Copilot plans', async () => {
    mockVerifiedFetch.mockResolvedValueOnce({ok: false})
    renderCopilotOrganizationAccessList()

    const dropdownButton = screen.getByRole('button', {name: /Copilot: Business/i})
    expect(dropdownButton).toBeInTheDocument()
    if (dropdownButton) {
      await act(async () => dropdownButton.click())
    }

    const copilotEnterpriseButton = screen.getByTestId(`org-copilot-plan-${firstOrganization.id}-enterprise`)
    expect(copilotEnterpriseButton).toBeInTheDocument()
    if (copilotEnterpriseButton) {
      await act(async () => copilotEnterpriseButton.click())
    }

    const upgradeConfirmationButton = screen.getByRole('button', {name: /Upgrade licenses/i})
    expect(upgradeConfirmationButton).toBeInTheDocument()
    await act(async () => upgradeConfirmationButton.click())

    const expectedFormData = new FormData()
    expectedFormData.append('enablement', 'enterprise')
    expectedFormData.append('organization_id', firstOrganization.id.toString())
    expect(mockVerifiedFetch).toHaveBeenCalledWith(
      '/enterprises/test-co/settings/update_copilot_individual_org_enablement',
      {
        method: 'PUT',
        body: expectedFormData,
      },
    )
    expect(screen.getByTestId('copilot-plan-change-error-banner')).toBeInTheDocument()
  })

  test('renders the grant access section if the EA has no orgs with copilot access, and no orgs whose copilot access can be reenabled', () => {
    renderCopilotOrganizationAccessList([], true)

    expect(screen.getByText('No organizations with access')).toBeInTheDocument()
    const grantAccessButton = screen.getByRole('button', {name: /Grant access/i})
    expect(grantAccessButton).toBeInTheDocument()
  })

  test('does not render the grant access section if the EA has orgs with copilot access, or orgs whose copilot access can be reenabled', () => {
    renderCopilotOrganizationAccessList()
    expect(screen.queryByText('No organizations with access')).not.toBeInTheDocument()
    const grantAccessButton = screen.queryByRole('button', {name: /Grant access/i})
    expect(grantAccessButton).not.toBeInTheDocument()
  })

  test('does not render the grant access section if the EA has orgs with copilot access, or orgs whose copilot access can be reenabled, but the applied filter does not result in any organizations being passed to the component', () => {
    renderCopilotOrganizationAccessList([], false)

    expect(screen.queryByText('No organizations with access')).not.toBeInTheDocument()
    const grantAccessButton = screen.queryByRole('button', {name: /Grant access/i})
    expect(grantAccessButton).not.toBeInTheDocument()
  })

  test('renders the CopilotOrganizationAccessList component, and associated dialog when a bulk plan downgrade is performed', async () => {
    renderCopilotOrganizationAccessList()
    expect(screen.getByTestId('licensing-copilot-organization-access-list-view')).toBeInTheDocument()

    // Bulk select both organizations
    const selectAllCheckbox = screen.getByRole('checkbox', {name: /Select all organizations/i})
    expect(selectAllCheckbox).toBeInTheDocument()
    await act(async () => selectAllCheckbox.click())

    // Verify that both organizations are selected
    const firstOrganizationCheckbox = screen.getByRole('checkbox', {name: `Select ${firstOrganization.login}`})
    const secondOrganizationCheckbox = screen.getByRole('checkbox', {name: `Select ${secondOrganization.login}`})
    expect(firstOrganizationCheckbox).toBeChecked()
    expect(secondOrganizationCheckbox).toBeChecked()

    const removeAccessButton = screen.getByRole('button', {name: /Remove access/i})
    expect(removeAccessButton).toBeInTheDocument()
    await act(async () => removeAccessButton.click())

    // Verify that the bulk disable dialog is displayed
    expect(screen.getByTestId('copilot-bulk-disable-confirm-dialog')).toBeInTheDocument()
  })

  test('handles submit for bulk disabling Copilot access for selected organizations', async () => {
    renderCopilotOrganizationAccessList()
    expect(screen.getByTestId('licensing-copilot-organization-access-list-view')).toBeInTheDocument()

    // Select org1
    const firstOrganizationCheckbox = screen.getByRole('checkbox', {name: `Select ${firstOrganization.login}`})
    expect(firstOrganizationCheckbox).toBeInTheDocument()
    await act(async () => firstOrganizationCheckbox.click())
    expect(firstOrganizationCheckbox).toBeChecked()

    // Select org2
    const secondOrganizationCheckbox = screen.getByRole('checkbox', {name: `Select ${secondOrganization.login}`})
    expect(secondOrganizationCheckbox).toBeInTheDocument()
    await act(async () => secondOrganizationCheckbox.click())
    expect(secondOrganizationCheckbox).toBeChecked()

    const thirdOrganizationCheckbox = screen.getByRole('checkbox', {name: `Select ${thirdOrganization.login}`})
    expect(thirdOrganizationCheckbox).not.toBeChecked()

    const removeAccessButton = screen.getByRole('button', {name: /Remove access/i})
    expect(removeAccessButton).toBeInTheDocument()
    await act(async () => removeAccessButton.click())

    expect(screen.getByTestId('copilot-bulk-disable-confirm-dialog')).toBeInTheDocument()

    const confirmButton = screen.getByRole('button', {name: /Disable Copilot/i})
    expect(confirmButton).toBeInTheDocument()
    await act(async () => confirmButton.click())

    // Verify the API call. Only org1 and org2 should be sent in the request.
    const expectedFormData = new FormData()
    expectedFormData.append('enablement', 'disable')
    expectedFormData.append('organizations[]', firstOrganization.id.toString())
    expectedFormData.append('organizations[]', secondOrganization.id.toString())

    expect(mockVerifiedFetch).toHaveBeenCalledWith('/enterprises/test-co/settings/update_copilot_bulk_org_enablement', {
      method: 'PUT',
      body: expectedFormData,
    })
  })

  test('handles error for bulk disabling Copilot access for selected organizations', async () => {
    mockVerifiedFetch.mockResolvedValueOnce({ok: false})
    renderCopilotOrganizationAccessList()
    expect(screen.getByTestId('licensing-copilot-organization-access-list-view')).toBeInTheDocument()

    // Select org1
    const firstOrganizationCheckbox = screen.getByRole('checkbox', {name: `Select ${firstOrganization.login}`})
    expect(firstOrganizationCheckbox).toBeInTheDocument()
    await act(async () => firstOrganizationCheckbox.click())
    expect(firstOrganizationCheckbox).toBeChecked()

    // Select org2
    const secondOrganizationCheckbox = screen.getByRole('checkbox', {name: `Select ${secondOrganization.login}`})
    expect(secondOrganizationCheckbox).toBeInTheDocument()
    await act(async () => secondOrganizationCheckbox.click())
    expect(secondOrganizationCheckbox).toBeChecked()

    const removeAccessButton = screen.getByRole('button', {name: /Remove access/i})
    expect(removeAccessButton).toBeInTheDocument()
    await act(async () => removeAccessButton.click())

    expect(screen.getByTestId('copilot-bulk-disable-confirm-dialog')).toBeInTheDocument()

    const confirmButton = screen.getByRole('button', {name: /Disable Copilot/i})
    expect(confirmButton).toBeInTheDocument()
    await act(async () => confirmButton.click())

    // Verify the API call. Only org1 and org2 should be sent in the request.
    const expectedFormData = new FormData()
    expectedFormData.append('enablement', 'disable')
    expectedFormData.append('organizations[]', firstOrganization.id.toString())
    expectedFormData.append('organizations[]', secondOrganization.id.toString())

    expect(mockVerifiedFetch).toHaveBeenCalledWith('/enterprises/test-co/settings/update_copilot_bulk_org_enablement', {
      method: 'PUT',
      body: expectedFormData,
    })

    expect(screen.getByTestId('copilot-disablement-error-banner')).toBeInTheDocument()
  })

  test('displays pagination controls when organizations exceed page size of 20', () => {
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

    renderCopilotOrganizationAccessList(manyOrgs)

    expect(screen.getByRole('navigation', {name: /Pagination/})).toBeInTheDocument()
    expect(screen.getByLabelText('Page 1')).toBeInTheDocument()
    expect(screen.getByLabelText('Page 2')).toBeInTheDocument()
  })
})

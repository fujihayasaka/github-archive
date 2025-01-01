import {fireEvent, screen, waitFor, within} from '@testing-library/react'
import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
import {BusinessTeamsCreateEditView} from '../routes/BusinessTeamsCreateEditView'
import {
  getBusinessTeamRoutePayload,
  getBusinessTeamRoutePayloadNoTeam,
  getOrganizationSuggestionsPayload,
} from '../test-utils/mock-data'
import {verifiedFetch, verifiedFetchJSON} from '@github-ui/verified-fetch'

const userEvent = setupUserEvent()

const mockVerifiedFetch = verifiedFetch as jest.Mock
const mockVerifiedFetchJSON = verifiedFetchJSON as jest.Mock
// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetch: jest.fn(),
  verifiedFetchJSON: jest.fn(),
}))

// Mock the useNavigate hook
jest.mock('@github-ui/use-navigate', () => ({
  useNavigate: jest.fn(() => jest.fn()),
}))

beforeEach(() => {
  mockVerifiedFetch.mockReset()
  mockVerifiedFetchJSON.mockReset()
})

test('Renders the BusinessTeamsCreateEditView for a New Team', () => {
  const routePayload = getBusinessTeamRoutePayloadNoTeam()
  render(<BusinessTeamsCreateEditView />, {
    routePayload,
  })

  // Verifies the creation heading is present when creating a new team
  const heading = screen.getByRole('heading', {level: 1})
  expect(heading).toHaveTextContent('Create Enterprise team')

  // Verifies the name change info is present when creating a new team
  // TODO: re-enable when @mentions for Business Teams have been implemented
  // const infoMessage = screen.getByText(/You'll use this name to mention this team./i)
  // expect(infoMessage).toBeInTheDocument()

  // Verifies the name input is empty when creating a new team
  const input = screen.getByTestId('business-team-name-input')
  expect(input).toHaveValue('')

  //Verifies the description input is empty when creating a new team
  const descriptionInput = screen.getByTestId('business-team-description')
  expect(descriptionInput).toHaveValue('')

  // Verifies the submission button for creating a new team
  const submissionButton = screen.getByRole('button', {name: 'Create Enterprise team'})
  expect(submissionButton).toBeInTheDocument()

  // Verifies the team organization assignment section for creating a new team
  const teamAccessFormControl = screen.getByText('Team access')
  expect(teamAccessFormControl).toBeInTheDocument()
})

test('Create Enterprise team button is inactive and shows a tooltip when limit has been reached', async () => {
  const routePayload = getBusinessTeamRoutePayloadNoTeam()
  routePayload.enterpriseTeamsLimitReached = true
  routePayload.enterpriseTeamsLimit = 1
  const {user} = render(<BusinessTeamsCreateEditView />, {
    routePayload,
  })

  // Verifies the submission button for creating a new team
  const submissionButton = screen.getByRole('button', {name: 'Create Enterprise team'})
  expect(submissionButton).toHaveAttribute('data-inactive', 'true')

  await user.hover(submissionButton)
  const toolTipLimit = screen.getByText(`Cannot add more teams, you've reached the 1-team limit.`)
  expect(toolTipLimit).toBeVisible()
})

test('Hides the Organization assignment section when creating a new team with M1 feature', () => {
  const routePayload = getBusinessTeamRoutePayloadNoTeam()
  routePayload.canSelectOrganizationAssignmentType = false
  render(<BusinessTeamsCreateEditView />, {
    routePayload,
  })

  // Verifies the team organization assignment section is not shown
  const teamAccessFormControl = screen.queryByText('Team access')
  expect(teamAccessFormControl).not.toBeInTheDocument()
})

test('Create new team submission triggers request with the correct parameters', async () => {
  const routePayload = getBusinessTeamRoutePayloadNoTeam()
  // @ts-expect-error overriding window.location in test
  delete window.location
  window.location = {
    replace: jest.fn(),
  } as unknown as string & Location
  render(<BusinessTeamsCreateEditView />, {
    routePayload,
  })
  mockVerifiedFetch.mockResolvedValue({
    ok: true,
    statusText: 'OK',
    json: async () => {
      return {
        data: {
          redirect: `/enterprises/${routePayload.enterpriseSlug}/teams/very-original-team-name`,
        },
      }
    },
  })
  // User name input
  const teamNameInput = screen.getByTestId('business-team-name-input')
  await userEvent.type(teamNameInput, 'Very Original Team Name')

  // Description input
  const teamDescriptionInput = screen.getByTestId('business-team-description')
  await userEvent.type(teamDescriptionInput, 'Very Original Team Description')

  // Submit form
  const submitBtn = screen.getByTestId('submit-button')
  await userEvent.click(submitBtn)

  await waitFor(() => {
    expect(mockVerifiedFetch).toHaveBeenCalledWith(`/enterprises/${routePayload.enterpriseSlug}/teams`, {
      method: 'POST',
      headers: {Accept: 'application/json'},
      body: expect.any(FormData),
    })
  })
  // Check the FormData content
  const formData = mockVerifiedFetch.mock.calls[0][1].body as FormData
  expect(formData.get('teamName')).toBe('Very Original Team Name')
  expect(formData.get('teamDescription')).toBe('Very Original Team Description')
  expect(formData.get('organizationSelectionType')).toBe('selected')

  // The created search param is used for displaying a flash message after the redirect
  expect(window.location.replace).toHaveBeenCalledWith('/enterprises/acme-corp/teams/very-original-team-name?created=1')
})

test('handles team name validation fail correctly and renders the error banner', async () => {
  const consoleErrorSpy = jest.spyOn(console, 'error').mockImplementation(() => {})
  const routePayload = getBusinessTeamRoutePayloadNoTeam()
  render(<BusinessTeamsCreateEditView />, {
    routePayload,
  })
  mockVerifiedFetch.mockResolvedValue({
    ok: false,
    statusText: 'BAD REQUEST',
    status: 400,
    json: async () => {
      return {
        data: {
          error: 'Name has already been taken',
        },
      }
    },
  })

  // User name input
  const teamNameInput = screen.getByTestId('business-team-name-input')
  await userEvent.type(teamNameInput, 'Very Original Team Name')

  // Submit form
  const submitBtn = screen.getByTestId('submit-button')
  await userEvent.click(submitBtn)

  await waitFor(() => {
    // Check if setFlash is called with the correct error message
    const flashMessage = screen.getByTestId('flash-error')
    expect(flashMessage).toHaveTextContent('Name has already been taken')
  })
  consoleErrorSpy.mockRestore()
})

test('handles bad request status code and renders the error banner', async () => {
  const consoleErrorSpy = jest.spyOn(console, 'error').mockImplementation(() => {})
  const routePayload = getBusinessTeamRoutePayloadNoTeam()
  render(<BusinessTeamsCreateEditView />, {
    routePayload,
  })
  mockVerifiedFetch.mockResolvedValue({
    ok: false,
    statusText: 'Bad Request',
    status: 400,
    json: async () => {
      return {
        data: {
          error: 'Invalid team name',
        },
      }
    },
  })

  // User name input
  const teamNameInput = screen.getByTestId('business-team-name-input')
  await userEvent.type(teamNameInput, 'Very Original Team Name')

  // Submit form
  const submitBtn = screen.getByTestId('submit-button')
  await userEvent.click(submitBtn)

  await waitFor(() => {
    // Check if setFlash is called with the correct error message
    const flashMessage = screen.getByTestId('flash-error')
    expect(flashMessage).toHaveTextContent('Invalid team name')
  })
  consoleErrorSpy.mockRestore()
})

test('handles generic server error banner while creating team', async () => {
  const consoleErrorSpy = jest.spyOn(console, 'error').mockImplementation(() => {})
  const routePayload = getBusinessTeamRoutePayloadNoTeam()
  render(<BusinessTeamsCreateEditView />, {
    routePayload,
  })
  mockVerifiedFetch.mockResolvedValue({
    ok: false,
    statusText: 'Internal Server Error',
    status: 500,
  })

  // User name input
  const teamNameInput = screen.getByTestId('business-team-name-input')
  await userEvent.type(teamNameInput, 'Very Original Team Name')

  // Submit form
  const submitBtn = screen.getByTestId('submit-button')
  await userEvent.click(submitBtn)

  await waitFor(() => {
    // Check if setFlash is called with the correct error message
    const flashMessage = screen.getByTestId('flash-error')
    expect(flashMessage).toHaveTextContent('Something went wrong while creating the team. Please try again later.')
  })
  consoleErrorSpy.mockRestore()
})

test('Renders the EnterpriseTeamManagement for Editing', async () => {
  const routePayload = getBusinessTeamRoutePayload()
  render(<BusinessTeamsCreateEditView />, {
    routePayload,
  })

  // Verifies the heading is "Edit team" when an enterpriseTeam is present
  const heading = screen.getByRole('heading', {level: 1})
  expect(heading).toHaveTextContent('Edit Enterprise team')

  // Verifies the name change warning is present when an enterpriseTeam is present
  // TODO: re-enable when @mentions for Business Teams have been implemented
  // const warningMessage = await screen.findByText(/Changing the team name will break past mentions/i)
  // const strongText = within(warningMessage).getByText(
  //   new RegExp(`@${routePayload.enterpriseSlug}/${routePayload.enterpriseTeam!.name}`, 'i'),
  // )
  // expect(strongText).toBeInTheDocument()

  // Verifies the name input is initialized with the enterpriseTeam name in edit mode
  const input = screen.getByTestId('business-team-name-input')
  expect(input).toHaveValue(routePayload.enterpriseTeam?.name)

  const descriptionInput = screen.getByTestId('business-team-description')
  expect(descriptionInput).toHaveValue(routePayload.enterpriseTeam?.description)

  // Verifies the submission button for editing an existing team
  const submissionButton = screen.getByRole('button', {name: 'Update team'})
  expect(submissionButton).toBeInTheDocument()

  // Verifies the team organization assignment section for editing an existing team
  const teamAccessFormControl = screen.getByText('Team access')
  expect(teamAccessFormControl).toBeInTheDocument()
})

test('Does not disable the Update Enterprise team button when limit has been reached', () => {
  const routePayload = getBusinessTeamRoutePayload()
  routePayload.enterpriseTeamsLimitReached = true
  render(<BusinessTeamsCreateEditView />, {
    routePayload,
  })

  // Verifies the submission button for creating a new team
  const submissionButton = screen.getByRole('button', {name: 'Update team'})
  expect(submissionButton).not.toHaveAttribute('disabled')
})

test('Hides the Organization assignment section when editing a team with M1 feature', () => {
  const routePayload = getBusinessTeamRoutePayload()
  routePayload.canSelectOrganizationAssignmentType = false
  render(<BusinessTeamsCreateEditView />, {
    routePayload,
  })

  // Verifies the team organization assignment section is not shown
  const teamAccessFormControl = screen.queryByText('Team access')
  expect(teamAccessFormControl).not.toBeInTheDocument()
})

test('Edit team submission triggers request with the correct parameters', async () => {
  const routePayload = getBusinessTeamRoutePayload()
  // @ts-expect-error overriding window.location in test
  delete window.location
  window.location = {
    replace: jest.fn(),
  } as unknown as string & Location
  render(<BusinessTeamsCreateEditView />, {
    routePayload,
  })
  mockVerifiedFetch.mockResolvedValue({
    ok: true,
    statusText: 'OK',
    json: async () => {
      return {
        data: {
          redirect: `/enterprises/${routePayload.enterpriseSlug}/teams/very-original-team-name`,
        },
      }
    },
  })

  // User name input
  const teamNameInput = screen.getByTestId('business-team-name-input')
  await userEvent.clear(teamNameInput)
  await userEvent.type(teamNameInput, 'Very Original Team Name')

  // Description input
  const teamDescriptionInput = screen.getByTestId('business-team-description')
  await userEvent.clear(teamDescriptionInput)
  await userEvent.type(teamDescriptionInput, 'Very Original Team Description')

  // Submit form
  const submitBtn = screen.getByTestId('submit-button')
  await userEvent.click(submitBtn)

  await waitFor(() => {
    expect(mockVerifiedFetch).toHaveBeenCalledWith(
      `/enterprises/${routePayload.enterpriseSlug}/teams/${routePayload.enterpriseTeam!.slug}`,
      {
        method: 'PUT',
        headers: {Accept: 'application/json'},
        body: expect.any(FormData),
      },
    )
  })
  // Check the FormData content
  const formData = mockVerifiedFetch.mock.calls[0][1].body as FormData
  expect(formData.get('teamName')).toBe('Very Original Team Name')
  expect(formData.get('teamDescription')).toBe('Very Original Team Description')
  expect(formData.get('organizationSelectionType')).toBe('selected')

  // The created search param is not used for displaying a flash message after the redirect when editing a team
  expect(window.location.replace).toHaveBeenCalledWith('/enterprises/acme-corp/teams/very-original-team-name')
})

test('handles team not found while updating team', async () => {
  const consoleErrorSpy = jest.spyOn(console, 'error').mockImplementation(() => {})
  const routePayload = getBusinessTeamRoutePayload()
  render(<BusinessTeamsCreateEditView />, {
    routePayload,
  })
  mockVerifiedFetch.mockResolvedValue({
    ok: false,
    statusText: 'Not Found',
    status: 404,
    json: async () => {
      return {
        data: {
          error: 'Team not found.',
        },
      }
    },
  })

  // User name input
  const teamNameInput = screen.getByTestId('business-team-name-input')
  await userEvent.type(teamNameInput, 'Very Original Team Name')

  // Submit form
  const submitBtn = screen.getByTestId('submit-button')
  await userEvent.click(submitBtn)

  await waitFor(() => {
    // Check if setFlash is called with the correct error message
    const flashMessage = screen.getByTestId('flash-error')
    expect(flashMessage).toHaveTextContent('Team not found.')
  })
  consoleErrorSpy.mockRestore()
})

test('handles generic server error banner while updating team', async () => {
  const consoleErrorSpy = jest.spyOn(console, 'error').mockImplementation(() => {})
  const routePayload = getBusinessTeamRoutePayload()
  render(<BusinessTeamsCreateEditView />, {
    routePayload,
  })
  mockVerifiedFetch.mockResolvedValue({
    ok: false,
    statusText: 'Internal Server Error',
    status: 500,
  })

  // User name input
  const teamNameInput = screen.getByTestId('business-team-name-input')
  await userEvent.type(teamNameInput, 'Very Original Team Name')

  // Submit form
  const submitBtn = screen.getByTestId('submit-button')
  await userEvent.click(submitBtn)

  await waitFor(() => {
    // Check if setFlash is called with the correct error message
    const flashMessage = screen.getByTestId('flash-error')
    expect(flashMessage).toHaveTextContent('Something went wrong while updating the team. Please try again later.')
  })
  consoleErrorSpy.mockRestore()
})

test('Edit team has the delete team button and deletes the team', async () => {
  const routePayload = getBusinessTeamRoutePayload()
  render(<BusinessTeamsCreateEditView />, {
    routePayload,
  })

  mockVerifiedFetch.mockResolvedValue({
    ok: true,
    statusText: 'OK',
    json: async () => {
      return {
        data: {
          redirect: `TODO`,
        },
      }
    },
  })

  // Verifies the delete team button is present
  const deleteButton = screen.getByTestId('delete-team')
  expect(deleteButton).toBeInTheDocument()

  // Click delete team button
  await userEvent.click(deleteButton)

  // Verifies the delete team dialog is open
  const dialog = screen.getByRole('dialog')
  expect(dialog).toBeInTheDocument()

  // Verifies the delete team dialog title
  const dialogTitle = screen.getByRole('heading', {name: 'Delete team'})
  expect(dialogTitle).toBeInTheDocument()

  // Clicks the delete team button in the dialog
  const deleteTeamButton = within(dialog).getByRole('button', {name: 'Delete team'})
  await userEvent.click(deleteTeamButton)

  // Verifies the delete team function is called
  await waitFor(() => {
    expect(mockVerifiedFetch).toHaveBeenCalledWith(`/enterprises/${routePayload.enterpriseSlug}/teams/bulk_delete`, {
      method: 'DELETE',
      headers: {Accept: 'application/json'},
      body: expect.any(FormData),
    })
  })
})

test('Hides selected organizations section when preventEditOrganizations is true', async () => {
  const routePayload = {
    ...getBusinessTeamRoutePayload(),
    preventEditOrganizations: true,
  }

  render(<BusinessTeamsCreateEditView />, {
    routePayload,
  })

  // Team access label is visible
  const teamAccessFormControl = screen.queryByText('Team access')
  expect(teamAccessFormControl).toBeInTheDocument()

  // Specific organizations should be visible
  const specificOrganizationsElement = screen.queryByText('Specific organizations')
  expect(specificOrganizationsElement).toBeInTheDocument()

  // Organization names should NOT appear
  expect(screen.queryByText('acme-corp-1')).not.toBeInTheDocument()
  expect(screen.queryByText('acme-corp-2')).not.toBeInTheDocument()
  expect(screen.queryByText('acme-corp-3')).not.toBeInTheDocument()

  // Select organizations button should NOT be visible
  const selectOrgsButton = screen.queryByTestId('select-orgs-button')
  expect(selectOrgsButton).not.toBeInTheDocument()
})

test('Renders all organizations with correct message for team access', async () => {
  const routePayload = {
    ...getBusinessTeamRoutePayload(),
    enterpriseTeam: {
      ...getBusinessTeamRoutePayload().enterpriseTeam,
      organizationSelectionType: 'all',
      selectedOrganizationsCount: 0,
    },
  }

  render(<BusinessTeamsCreateEditView />, {
    routePayload,
  })

  // Verifies all organizations text
  const allOrganizationsElement = screen.getByText('All organizations')
  expect(allOrganizationsElement).toBeInTheDocument()

  // Verifies number of orgs
  const organizationCount = within(allOrganizationsElement).getByText('6')
  expect(organizationCount).toBeInTheDocument()

  // Verifies team org access
  const teamAccessMessage = screen.getByText('Your team will have access to all organizations')
  expect(teamAccessMessage).toBeInTheDocument()

  // Verifies more text appears
  const fullMessage = screen.getByText(content => {
    return (
      content.includes('Your team will have access to all 6 organizations.') &&
      content.includes('You can change this access after creation in the team settings page.')
    )
  })
  expect(fullMessage).toBeInTheDocument()
})

test('Renders all organizations but hides team access message when preventEditOrganizations is true', async () => {
  const routePayload = {
    ...getBusinessTeamRoutePayload(),
    enterpriseTeam: {
      ...getBusinessTeamRoutePayload().enterpriseTeam,
      organizationSelectionType: 'all',
      selectedOrganizationsCount: 0,
    },
    preventEditOrganizations: true,
  }

  render(<BusinessTeamsCreateEditView />, {
    routePayload,
  })

  // Verifies all organizations text
  const allOrganizationsElement = screen.getByText('All organizations')
  expect(allOrganizationsElement).toBeInTheDocument()

  // Verifies number of orgs
  const organizationCount = within(allOrganizationsElement).getByText('6')
  expect(organizationCount).toBeInTheDocument()

  // Verifies team org access message is NOT present
  const teamAccessMessage = screen.queryByText(/Your team will have access/i)
  expect(teamAccessMessage).not.toBeInTheDocument()

  // Verifies more text does NOT appear
  const fullMessage = screen.queryByText(content => {
    return (
      content.includes('Your team will have access to all 6 organizations.') &&
      content.includes('You can change this access after creation in the team settings page.')
    )
  })
  expect(fullMessage).not.toBeInTheDocument()
})

test('Renders blank state for no selected organizations', async () => {
  const routePayload = {
    ...getBusinessTeamRoutePayload(),
    enterpriseTeam: {
      ...getBusinessTeamRoutePayload().enterpriseTeam,
      selectedOrganizationsCount: 0,
    },
  }
  render(<BusinessTeamsCreateEditView />, {
    routePayload,
  })

  // Verifies specific organizations text
  const specificOrganizationsElement = screen.getByText('Specific organizations')
  expect(specificOrganizationsElement).toBeInTheDocument()

  // Verifies number of orgs
  const organizationCount = within(specificOrganizationsElement).getByText('0')
  expect(organizationCount).toBeInTheDocument()

  // Verifies blank state text
  const firstline = screen.getByText('Your team will have access to the selected organizations')
  expect(firstline).toBeInTheDocument()

  const secondLine = screen.getByText('Choose the organizations where your team members will be added.')
  expect(secondLine).toBeInTheDocument()

  // Expect select orgs button to be enabled
  const selectOrgsButton = screen.getByTestId('select-orgs-button')
  expect(selectOrgsButton).toBeVisible()
  expect(selectOrgsButton).toBeEnabled()
})

test('Renders specific organizations, and delete one', async () => {
  const consoleErrorSpy = jest.spyOn(console, 'error').mockImplementation(() => {})
  const routePayload = getBusinessTeamRoutePayload()
  render(<BusinessTeamsCreateEditView />, {
    routePayload,
  })
  mockVerifiedFetch.mockResolvedValue({
    ok: true,
    statusText: 'OK',
    json: async () => {
      return {
        data: {
          redirect: `/enterprises/${routePayload.enterpriseSlug}/teams/very-original-team-name`,
        },
      }
    },
  })
  mockVerifiedFetchJSON.mockResolvedValue({
    json: async () => getOrganizationSuggestionsPayload(),
    ok: true,
  })

  // Verifies specific organizations text
  const specificOrganizationsElement = screen.getByText('Specific organizations')
  expect(specificOrganizationsElement).toBeInTheDocument()

  // Verifies number of orgs
  const organizationCount = within(specificOrganizationsElement).getByText('3')
  expect(organizationCount).toBeInTheDocument()

  // Add an organization
  const selectOrgsButton = screen.getByTestId('select-orgs-button')
  expect(selectOrgsButton).toBeVisible()

  await userEvent.click(selectOrgsButton)
  const org1 = screen.getByTestId('org-1')
  expect(org1).toBeInTheDocument()
  await userEvent.click(org1)
  const addOrgsButton = screen.getByTestId('add-orgs')
  expect(addOrgsButton).toHaveTextContent('Add 1')
  await userEvent.click(addOrgsButton)

  // Delete that organization
  const deleteOrgButton = screen.getByLabelText('Remove A first org from the team')
  expect(deleteOrgButton).toBeInTheDocument()
  await userEvent.click(deleteOrgButton)
  expect(screen.queryByText('A first org')).not.toBeInTheDocument()

  // Submit form
  const submitBtn = screen.getByTestId('submit-button')
  await userEvent.click(submitBtn)

  await waitFor(() => {
    expect(mockVerifiedFetch).toHaveBeenCalledWith(
      `/enterprises/${routePayload.enterpriseSlug}/teams/${routePayload.enterpriseTeam!.slug}`,
      {
        method: 'PUT',
        headers: {Accept: 'application/json'},
        body: expect.any(FormData),
      },
    )
  })

  // Check the FormData content
  const formData = mockVerifiedFetch.mock.calls[0][1].body as FormData
  expect(formData.get('organizationSelectionType')).toBe('selected')

  consoleErrorSpy.mockRestore()
})

test('Renders none for team access with no organizations selected', async () => {
  const routePayload = {
    ...getBusinessTeamRoutePayload(),
    enterpriseTeam: {
      ...getBusinessTeamRoutePayload().enterpriseTeam,
      organizationSelectionType: 'none',
      selectedOrganizationsCount: 0,
    },
  }

  render(<BusinessTeamsCreateEditView />, {
    routePayload,
  })

  // Verifies none text
  const noneElement = screen.getByText('None')
  expect(noneElement).toBeInTheDocument()

  // Verifies no organizations appear
  expect(screen.queryByText('acme-corp-1')).not.toBeInTheDocument()
  expect(screen.queryByText('acme-corp-2')).not.toBeInTheDocument()
  expect(screen.queryByText('acme-corp-3')).not.toBeInTheDocument()
})

test('Renders orgs at the limit', async () => {
  const consoleErrorSpy = jest.spyOn(console, 'error').mockImplementation(() => {})
  const routePayload = getBusinessTeamRoutePayloadNoTeam()
  routePayload.enterpriseTeamsOrgAssignmentLimit = 3
  render(<BusinessTeamsCreateEditView />, {
    routePayload,
  })
  mockVerifiedFetch.mockResolvedValueOnce({
    ok: true,
    statusText: 'OK',
    json: async () => {
      return {
        data: {
          redirect: `/enterprises/${routePayload.enterpriseSlug}/teams/very-original-team-name`,
        },
      }
    },
  })

  mockVerifiedFetchJSON.mockResolvedValueOnce({
    json: async () => getOrganizationSuggestionsPayload(),
    ok: true,
  })

  const bannerText = '3-organization limit reached. You can add more after team creation in the organizations section.'
  expect(screen.queryByText(bannerText)).not.toBeInTheDocument()

  // Add organizations to reach the max
  let selectOrgsButton = screen.getByTestId('select-orgs-button')
  expect(selectOrgsButton).toBeVisible()

  await userEvent.click(selectOrgsButton)
  const org1 = screen.getByTestId('org-1')
  await userEvent.click(org1)
  const org2 = screen.getByTestId('org-2')
  await userEvent.click(org2)
  const org3 = screen.getByTestId('org-3')
  await userEvent.click(org3)

  const addOrgsButton = screen.getByTestId('add-orgs')
  expect(addOrgsButton).toHaveTextContent('Add 3')
  await userEvent.click(addOrgsButton)

  // Check banner message is now visible
  expect(screen.getByText(bannerText)).toBeVisible()

  // Check tooltip message
  const tooltipText = screen.getByText("You can't select more organizations — you've reached the 3-organization limit.")
  expect(tooltipText).toBeInTheDocument()

  // Delete an organization
  const deleteOrgButton = screen.getByLabelText('Remove A first org from the team')
  await userEvent.click(deleteOrgButton)
  expect(screen.queryByText('A first org')).not.toBeInTheDocument()

  // Select orgs is enabled again
  selectOrgsButton = screen.getByTestId('select-orgs-button')
  expect(selectOrgsButton).not.toHaveAttribute('data-inactive')
  expect(
    screen.queryByText(
      '3-organization limit reached. You can add more after team creation in the organizations section.',
    ),
  ).not.toBeInTheDocument()
  expect(
    screen.queryByText("You can't select more organizations—you've reached the 3-organization limit."),
  ).not.toBeInTheDocument()

  consoleErrorSpy.mockRestore()
})

test('Character counter correctly displays count for team description input', () => {
  const routePayload = getBusinessTeamRoutePayloadNoTeam()
  render(<BusinessTeamsCreateEditView />, {
    routePayload,
  })

  const teamDescriptionInput = screen.getByTestId('business-team-description')
  const counter = screen.getByTestId('team-description-counter')
  expect(counter).toBeInTheDocument()
  expect(counter).toHaveTextContent('0/350')

  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.change(teamDescriptionInput, {target: {value: 'A'.repeat(10)}})
  expect(counter).toHaveTextContent('10/350')

  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.change(teamDescriptionInput, {target: {value: ''}})
  expect(counter).toHaveTextContent('0/350')

  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.change(teamDescriptionInput, {target: {value: 'A'.repeat(351)}})
  expect(counter).toHaveTextContent('351/350')
})

test('Renders the BusinessTeamMembersManagement component when isMembersManagementEnabled is true', () => {
  const routePayload = getBusinessTeamRoutePayloadNoTeam()
  routePayload.isMembersManagementEnabled = true
  render(<BusinessTeamsCreateEditView />, {
    routePayload,
  })

  // Check for the presence of the Identity Provider Group section
  const manageMembers = screen.getByText('Manage members')
  expect(manageMembers).toBeInTheDocument()
})

test('Does not render the BusinessTeamMembersManagement component when isMembersManagementEnabled is false', () => {
  const routePayload = getBusinessTeamRoutePayloadNoTeam()
  routePayload.isMembersManagementEnabled = false
  render(<BusinessTeamsCreateEditView />, {
    routePayload,
  })

  // Check that Identity Provider Group section is not shown
  const manageMembers = screen.queryByText('Manage members')
  expect(manageMembers).not.toBeInTheDocument()
})

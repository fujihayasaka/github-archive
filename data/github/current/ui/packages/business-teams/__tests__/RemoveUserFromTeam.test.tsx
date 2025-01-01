import {fireEvent, screen, waitFor, within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {getBusinessTeamMembersViewRoutePayload} from '../test-utils/mock-data'
import {BusinessTeamMembersView} from '../routes/BusinessTeamMembersView'
import {verifiedFetch} from '@github-ui/verified-fetch'

const mockVerifiedFetch = verifiedFetch as jest.Mock
// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetch: jest.fn(),
}))

test('Renders remove 1 member dialog', async () => {
  const routePayload = getBusinessTeamMembersViewRoutePayload()
  const {user} = render(<BusinessTeamMembersView />, {
    routePayload,
  })

  const listItem = screen.getByTestId('list-item-1')
  expect(listItem).toBeInTheDocument()

  const memberActions = within(listItem).getByRole('button', {name: 'More member actions'})
  expect(memberActions).toBeVisible()

  // It doesn't work with await user.click(removeMemberAction) "Element requested is not a known focusable element."
  // Couldn't find a solution and no other similar code I compared this to seems to have the issue.
  // Can actually focus the element and action it with a keyboard in the actual UI. Forcing focus in test doesn't help.
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(memberActions)

  const removeAction = screen.getByTestId('remove-member-1')
  expect(removeAction).toBeVisible()
  await user.click(removeAction)

  const removeDialog = screen.getByRole('dialog', {name: 'Remove member'})
  expect(removeDialog).toBeVisible()

  const description = within(removeDialog).getByTestId('remove-members-dialog-description')
  expect(description).toBeVisible()
  expect(description).toHaveTextContent("You're about to remove 1 member from the Acme Engineering team.")

  const listDescription = within(removeDialog).queryByTestId('remove-members-dialog-list-description')
  expect(listDescription).not.toBeInTheDocument()

  const memberLogin = within(removeDialog).getByTestId('remove-members-dialog-member-login-1')
  expect(memberLogin).toBeVisible()
  expect(memberLogin).toHaveTextContent('hubot')

  const memberName = within(removeDialog).getByTestId('remove-members-dialog-member-name-1')
  expect(memberName).toBeVisible()
  expect(memberName).toHaveTextContent('hubot')

  const impactDescription = within(removeDialog).getByTestId('remove-members-dialog-impact-description')
  expect(impactDescription).toBeVisible()
  expect(impactDescription).toHaveTextContent('Removed member might lose permissions to organizations or repositories.')

  expect(screen.getByRole('button', {name: 'Cancel'})).toBeVisible()
  expect(screen.getByRole('button', {name: 'Remove member'})).toBeVisible()
})

test('Cancel remove 1 member dialog', async () => {
  const routePayload = getBusinessTeamMembersViewRoutePayload()
  const {user} = render(<BusinessTeamMembersView />, {
    routePayload,
  })

  const listItem = screen.getByTestId('list-item-1')
  const memberActions = within(listItem).getByRole('button', {name: 'More member actions'})
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(memberActions)
  const removeAction = screen.getByTestId('remove-member-1')
  await user.click(removeAction)

  const removeDialog = screen.getByRole('dialog', {name: 'Remove member'})
  expect(removeDialog).toBeVisible()

  await user.click(screen.getByRole('button', {name: 'Cancel'}))

  expect(removeDialog).not.toBeVisible()
})

test('Remove 1 member successfully', async () => {
  mockVerifiedFetch.mockResolvedValue({
    ok: true,
    statusText: 'OK',
    json: async () => {
      return {
        redirect: '/enterprises/acme-corp/teams/acme-engineering/members',
      }
    },
  })

  const routePayload = getBusinessTeamMembersViewRoutePayload()
  const {user} = render(<BusinessTeamMembersView />, {
    routePayload,
  })

  const listItem = screen.getByTestId('list-item-1')
  const memberActions = within(listItem).getByRole('button', {name: 'More member actions'})
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(memberActions)
  const removeAction = screen.getByTestId('remove-member-1')
  await user.click(removeAction)

  const removeDialog = screen.getByRole('dialog', {name: 'Remove member'})
  expect(removeDialog).toBeVisible()

  await user.click(screen.getByRole('button', {name: 'Remove member'}))

  await waitFor(() => {
    expect(mockVerifiedFetch).toHaveBeenCalledWith(
      `/enterprises/acme-corp/teams/acme-engineering/members/bulk_delete`,
      {
        method: 'DELETE',
        headers: {Accept: 'application/json'},
        body: expect.any(FormData),
      },
    )
  })

  const formData = mockVerifiedFetch.mock.calls[0][1].body as FormData
  const formDataEntries: Record<string, string> = {}
  for (const [key, value] of formData.entries()) {
    formDataEntries[key] = value as string
  }

  expect(formDataEntries).toEqual({
    'user_ids[]': '1',
  })
})

test('Remove 1 member unexpected error', async () => {
  mockVerifiedFetch.mockResolvedValue({
    ok: false,
    status: 500,
    statusText: 'Internal Server Error',
  })

  const routePayload = getBusinessTeamMembersViewRoutePayload()
  const {user} = render(<BusinessTeamMembersView />, {
    routePayload,
  })

  const listItem = screen.getByTestId('list-item-1')
  const memberActions = within(listItem).getByRole('button', {name: 'More member actions'})
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(memberActions)
  let removeAction = screen.getByTestId('remove-member-1')
  await user.click(removeAction)

  const removeDialog = screen.getByRole('dialog', {name: 'Remove member'})
  expect(removeDialog).toBeVisible()

  await user.click(screen.getByRole('button', {name: 'Remove member'}))

  await waitFor(() => {
    expect(mockVerifiedFetch).toHaveBeenCalledWith(
      `/enterprises/acme-corp/teams/acme-engineering/members/bulk_delete`,
      {
        method: 'DELETE',
        headers: {Accept: 'application/json'},
        body: expect.any(FormData),
      },
    )
  })

  const flash = screen.getByTestId('flash-error')
  expect(flash).toBeVisible()
  expect(flash).toHaveTextContent('An error occurred while removing members.')

  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(memberActions)
  removeAction = screen.getByTestId('remove-member-1')
  await user.click(removeAction)
  expect(flash).not.toBeInTheDocument()
})

test('Remove 1 member json error', async () => {
  mockVerifiedFetch.mockResolvedValue({
    ok: false,
    status: 404,
    statusText: 'Inernal Server Error',
    json: async () => {
      return {
        data: {error: 'Team not found.'},
      }
    },
  })

  const routePayload = getBusinessTeamMembersViewRoutePayload()
  const {user} = render(<BusinessTeamMembersView />, {
    routePayload,
  })

  const listItem = screen.getByTestId('list-item-1')
  const memberActions = within(listItem).getByRole('button', {name: 'More member actions'})
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(memberActions)
  const removeAction = screen.getByTestId('remove-member-1')
  await user.click(removeAction)

  const removeDialog = screen.getByRole('dialog', {name: 'Remove member'})
  expect(removeDialog).toBeVisible()

  await user.click(screen.getByRole('button', {name: 'Remove member'}))

  await waitFor(() => {
    expect(mockVerifiedFetch).toHaveBeenCalledWith(
      `/enterprises/acme-corp/teams/acme-engineering/members/bulk_delete`,
      {
        method: 'DELETE',
        headers: {Accept: 'application/json'},
        body: expect.any(FormData),
      },
    )
  })

  const flash = screen.getByTestId('flash-error')
  expect(flash).toBeVisible()
  expect(flash).toHaveTextContent('Team not found.')
})

test('Remove 1 member error with unexpected json', async () => {
  mockVerifiedFetch.mockResolvedValue({
    ok: false,
    status: 404,
    statusText: 'Inernal Server Error',
    json: async () => {
      return {}
    },
  })

  const routePayload = getBusinessTeamMembersViewRoutePayload()
  const {user} = render(<BusinessTeamMembersView />, {
    routePayload,
  })

  const listItem = screen.getByTestId('list-item-1')
  const memberActions = within(listItem).getByRole('button', {name: 'More member actions'})
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(memberActions)
  const removeAction = screen.getByTestId('remove-member-1')
  await user.click(removeAction)

  const removeDialog = screen.getByRole('dialog', {name: 'Remove member'})
  expect(removeDialog).toBeVisible()

  await user.click(screen.getByRole('button', {name: 'Remove member'}))

  await waitFor(() => {
    expect(mockVerifiedFetch).toHaveBeenCalledWith(
      `/enterprises/acme-corp/teams/acme-engineering/members/bulk_delete`,
      {
        method: 'DELETE',
        headers: {Accept: 'application/json'},
        body: expect.any(FormData),
      },
    )
  })

  const flash = screen.getByTestId('flash-error')
  expect(flash).toBeVisible()
  expect(flash).toHaveTextContent('An error occurred while removing members.')
})

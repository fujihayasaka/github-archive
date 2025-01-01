import {fireEvent, screen, waitFor, within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {getBusinessTeamOrganizationsViewRoutePayload} from '../test-utils/mock-data'
import {BusinessTeamOrganizationsView} from '../routes/BusinessTeamOrganizationsView'
import {verifiedFetch, verifiedFetchJSON} from '@github-ui/verified-fetch'

const mockVerifiedFetch = verifiedFetch as jest.Mock
const mockVerifiedFetchJSON = verifiedFetchJSON as jest.Mock
// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetchJSON: jest.fn(),
  verifiedFetch: jest.fn(),
}))

beforeEach(() => {
  mockVerifiedFetchJSON.mockReset()
  mockVerifiedFetch.mockReset()
})

test('Renders remove 1 org dialog', async () => {
  const routePayload = getBusinessTeamOrganizationsViewRoutePayload()
  const {user} = render(<BusinessTeamOrganizationsView />, {
    routePayload,
  })

  const listItem = screen.getByTestId('list-item-1')
  expect(listItem).toBeInTheDocument()

  const orgActions = within(listItem).getByRole('button', {name: 'More organization actions'})
  expect(orgActions).toBeVisible()

  // It doesn't work with await user.click(removeMemberAction) "Element requested is not a known focusable element."
  // Couldn't find a solution and no other similar code I compared this to seems to have the issue.
  // Can actually focus the element and action it with a keyboard in the actual UI. Forcing focus in test doesn't help.
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(orgActions)

  const removeAction = screen.getByTestId('remove-org-1')
  expect(removeAction).toBeVisible()
  await user.click(removeAction)

  const removeDialog = screen.getByRole('dialog', {name: 'Remove organization'})
  expect(removeDialog).toBeVisible()

  const description = within(removeDialog).getByTestId('remove-orgs-dialog-header')
  expect(description).toBeVisible()
  expect(description).toHaveTextContent("You're about to remove the Acme Engineering team from 1 organization.")

  const orgLogin = within(removeDialog).getByTestId('remove-orgs-dialog-org-login-1')
  expect(orgLogin).toBeVisible()
  expect(orgLogin).toHaveTextContent('A first org')

  const impactDescription = within(removeDialog).getByTestId('remove-orgs-dialog-impact-description')
  expect(impactDescription).toBeVisible()
  expect(impactDescription).toHaveTextContent(
    'Members of the team might lose permissions to the removed organizations and their repositories.',
  )

  expect(screen.getByRole('button', {name: 'Cancel'})).toBeVisible()
  expect(screen.getByRole('button', {name: 'Remove organization'})).toBeVisible()
})

test('Cancel remove 1 org dialog', async () => {
  const routePayload = getBusinessTeamOrganizationsViewRoutePayload()
  const {user} = render(<BusinessTeamOrganizationsView />, {
    routePayload,
  })

  const listItem = screen.getByTestId('list-item-1')
  const orgActions = within(listItem).getByRole('button', {name: 'More organization actions'})
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(orgActions)
  const removeAction = screen.getByTestId('remove-org-1')
  await user.click(removeAction)

  const removeDialog = screen.getByRole('dialog', {name: 'Remove organization'})
  expect(removeDialog).toBeVisible()

  await user.click(screen.getByRole('button', {name: 'Cancel'}))

  expect(removeDialog).not.toBeVisible()
})

test('Remove 1 org successfully', async () => {
  mockVerifiedFetch.mockResolvedValue({
    ok: true,
    statusText: 'OK',
    json: async () => {
      return {
        message: 'Organizations removed successfully',
      }
    },
  })

  const routePayload = getBusinessTeamOrganizationsViewRoutePayload()
  const {user} = render(<BusinessTeamOrganizationsView />, {
    routePayload,
  })

  const listItem = screen.getByTestId('list-item-1')
  const orgActions = within(listItem).getByRole('button', {name: 'More organization actions'})
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(orgActions)
  const removeAction = screen.getByTestId('remove-org-1')
  await user.click(removeAction)

  const removeDialog = screen.getByRole('dialog', {name: 'Remove organization'})
  expect(removeDialog).toBeVisible()

  mockVerifiedFetchJSON.mockResolvedValueOnce({
    json: async () => ({
      payload: routePayload,
    }),
    ok: true,
  })

  await user.click(screen.getByRole('button', {name: 'Remove organization'}))

  await waitFor(() => {
    expect(mockVerifiedFetch).toHaveBeenCalledWith(
      `/enterprises/acme-corp/teams/acme-engineering/organizations/bulk_delete`,
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
    'organization_ids[]': '1',
  })
})

test('Remove 1 org unexpected error', async () => {
  mockVerifiedFetch.mockResolvedValue({
    ok: false,
    status: 500,
    statusText: 'Internal Server Error',
  })

  const routePayload = getBusinessTeamOrganizationsViewRoutePayload()
  const {user} = render(<BusinessTeamOrganizationsView />, {
    routePayload,
  })

  const listItem = screen.getByTestId('list-item-1')
  const orgActions = within(listItem).getByRole('button', {name: 'More organization actions'})
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(orgActions)
  let removeAction = screen.getByTestId('remove-org-1')
  await user.click(removeAction)

  const removeDialog = screen.getByRole('dialog', {name: 'Remove organization'})
  expect(removeDialog).toBeVisible()

  await user.click(screen.getByRole('button', {name: 'Remove organization'}))

  await waitFor(() => {
    expect(mockVerifiedFetch).toHaveBeenCalledWith(
      `/enterprises/acme-corp/teams/acme-engineering/organizations/bulk_delete`,
      {
        method: 'DELETE',
        headers: {Accept: 'application/json'},
        body: expect.any(FormData),
      },
    )
  })

  const flash = screen.getByTestId('flash-error')
  expect(flash).toBeVisible()
  expect(flash).toHaveTextContent('Failed to delete organizations from team acme-engineering')

  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(orgActions)
  removeAction = screen.getByTestId('remove-org-1')
  await user.click(removeAction)
  expect(flash).not.toBeInTheDocument()
})

test('Remove 1 org json error', async () => {
  mockVerifiedFetch.mockResolvedValue({
    ok: false,
    json: async () => {
      return {
        error: 'Invalid selection type',
      }
    },
  })

  const routePayload = getBusinessTeamOrganizationsViewRoutePayload()
  const {user} = render(<BusinessTeamOrganizationsView />, {
    routePayload,
  })

  const listItem = screen.getByTestId('list-item-1')
  const orgActions = within(listItem).getByRole('button', {name: 'More organization actions'})
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(orgActions)
  const removeAction = screen.getByTestId('remove-org-1')
  await user.click(removeAction)

  const removeDialog = screen.getByRole('dialog', {name: 'Remove organization'})
  expect(removeDialog).toBeVisible()

  await user.click(screen.getByRole('button', {name: 'Remove organization'}))

  await waitFor(() => {
    expect(mockVerifiedFetch).toHaveBeenCalledWith(
      `/enterprises/acme-corp/teams/acme-engineering/organizations/bulk_delete`,
      {
        method: 'DELETE',
        headers: {Accept: 'application/json'},
        body: expect.any(FormData),
      },
    )
  })

  const flash = screen.getByTestId('flash-error')
  expect(flash).toBeVisible()
  expect(flash).toHaveTextContent('Invalid selection type')
})

test('Remove 1 org error with unexpected json', async () => {
  mockVerifiedFetch.mockResolvedValue({
    ok: false,
    status: 404,
    statusText: 'Inernal Server Error',
    json: async () => {
      return {}
    },
  })

  const routePayload = getBusinessTeamOrganizationsViewRoutePayload()
  const {user} = render(<BusinessTeamOrganizationsView />, {
    routePayload,
  })

  const listItem = screen.getByTestId('list-item-1')
  const orgActions = within(listItem).getByRole('button', {name: 'More organization actions'})
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(orgActions)
  const removeAction = screen.getByTestId('remove-org-1')
  await user.click(removeAction)

  const removeDialog = screen.getByRole('dialog', {name: 'Remove organization'})
  expect(removeDialog).toBeVisible()

  await user.click(screen.getByRole('button', {name: 'Remove organization'}))

  await waitFor(() => {
    expect(mockVerifiedFetch).toHaveBeenCalledWith(
      `/enterprises/acme-corp/teams/acme-engineering/organizations/bulk_delete`,
      {
        method: 'DELETE',
        headers: {Accept: 'application/json'},
        body: expect.any(FormData),
      },
    )
  })

  const flash = screen.getByTestId('flash-error')
  expect(flash).toBeVisible()
  expect(flash).toHaveTextContent('Failed to delete organizations from team acme-engineering')
})

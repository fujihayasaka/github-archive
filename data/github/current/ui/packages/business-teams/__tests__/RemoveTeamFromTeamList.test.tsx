import {fireEvent, screen, within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {BusinessTeamsListView} from '../routes/BusinessTeamsListView'
import {verifiedFetch, verifiedFetchJSON} from '@github-ui/verified-fetch'
import {getBusinessTeamsTableViewRoutePayload} from '../test-utils/mock-data'

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

test('Renders remove 1 team dialog', async () => {
  const routePayload = getBusinessTeamsTableViewRoutePayload()
  const {user} = render(<BusinessTeamsListView />, {
    routePayload,
  })

  const listItem = screen.getByTestId('list-item-1')
  expect(listItem).toBeInTheDocument()

  const teamActions = within(listItem).getByRole('button', {name: 'More list item action bar'})
  expect(teamActions).toBeVisible()

  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(teamActions)

  const deleteAction = screen.getByTestId('remove-team-1')
  expect(deleteAction).toBeVisible()
  await user.click(deleteAction)

  const deleteDialog = screen.getByRole('dialog', {name: 'Delete team'})
  expect(deleteDialog).toBeVisible()

  const title = within(deleteDialog).getByRole('heading')
  expect(title).toBeVisible()
  expect(title).toHaveTextContent(/delete team/i)

  const description = within(deleteDialog).getByTestId('delete-team-description')
  expect(description).toBeVisible()
  expect(description.textContent).toMatch(/you're about to delete 1 enterprise team/i)

  const impactDescription = within(deleteDialog).getByTestId('remove-one-team-dialog-impact-description')
  expect(impactDescription).toBeVisible()
  expect(impactDescription.textContent).toMatch(
    /this action cannot be undone and will remove this team's configuration, including its membership list and permission settings. Any access grants through the team will also be removed./i,
  )

  expect(screen.getByRole('button', {name: 'Cancel'})).toBeVisible()
  expect(screen.getByRole('button', {name: 'Delete team'})).toBeVisible()
})

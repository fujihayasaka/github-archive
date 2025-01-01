import {screen, act} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {getAddUserToTeamButtonProps} from '../test-utils/mock-data'
import AddUserToTeamButton from '../components/AddUserToTeamButton'

beforeEach(() => {
  const mockReturnValue = {
    users: [
      {
        displayLogin: 'user-one',
        id: 1,
        profileName: 'User One',
        avatarUrl: 'http://alambic.github.localhost/avatars/u/1',
      },
      {
        displayLogin: 'user-two',
        id: 2,
        profileName: 'User Two',
        avatarUrl: 'http://alambic.github.localhost/avatars/u/2',
      },
    ],
    totalEligibleUsersInEnterprise: 2,
  }
  jest.spyOn(global, 'fetch').mockResolvedValueOnce({
    json: async () => mockReturnValue,
    ok: true,
  } as Response)
})
const props = getAddUserToTeamButtonProps()

test('Renders users when opened', async () => {
  const {user} = render(<AddUserToTeamButton {...props} />)
  const addMemberButton = screen.getByTestId('add-members-button')
  expect(addMemberButton).toBeInTheDocument()
  await user.click(addMemberButton)
  expect(screen.getByTestId('enterprise-member-0')).toBeInTheDocument()
  expect(screen.getByTestId('enterprise-member-1')).toBeInTheDocument()
})

test('Searching for a nonexistent user displays an error', async () => {
  jest.useFakeTimers()
  const mockReturnValue = {
    users: [],
    totalEligibleUsersInEnterprise: 2,
  }
  jest.spyOn(global, 'fetch').mockResolvedValueOnce({
    json: async () => mockReturnValue,
    ok: true,
  } as Response)
  const {user} = render(<AddUserToTeamButton {...props} />)
  const addMemberButton = screen.getByTestId('add-members-button')
  await user.click(addMemberButton)
  const searchInput = screen.getByTestId('search-members-input')
  await user.type(searchInput, 'user-three')
  act(jest.runOnlyPendingTimers)
  const text = await screen.findByTestId('no-users-found-text')
  expect(text).toBeInTheDocument()
})

test('Select all toggles selection', async () => {
  const {user} = render(<AddUserToTeamButton {...props} />)
  const addMemberButton = screen.getByTestId('add-members-button')
  await user.click(addMemberButton)
  const selectAllCheckbox = screen.getByTestId('select-all-checkbox')
  const userOneCheckbox = screen.getByTestId('enterprise-member-0')
  const userTwoCheckbox = screen.getByTestId('enterprise-member-1')

  await user.click(selectAllCheckbox)
  expect(selectAllCheckbox).toHaveAttribute('aria-checked', 'true')
  expect(userOneCheckbox).toHaveAttribute('aria-selected', 'true')
  expect(userTwoCheckbox).toHaveAttribute('aria-selected', 'true')
  await user.click(selectAllCheckbox)
  expect(selectAllCheckbox).toHaveAttribute('aria-checked', 'false')
  expect(userOneCheckbox).toHaveAttribute('aria-selected', 'false')
  expect(userTwoCheckbox).toHaveAttribute('aria-selected', 'false')
})

test('Save is disabled and error banner is displayed when adding more members than allowed', async () => {
  props.membersAllowedToAdd = 1
  props.teamMembersLimit = 1
  const {user} = render(<AddUserToTeamButton {...props} />)
  const addMemberButton = screen.getByTestId('add-members-button')
  await user.click(addMemberButton)
  const selectAllCheckbox = screen.getByTestId('select-all-checkbox')

  await user.click(selectAllCheckbox)
  const membersLimitBanner = screen.getByTestId('team-members-limit-error')
  expect(membersLimitBanner).toBeInTheDocument()
  const saveButton = screen.getByRole('button', {name: 'Save'})
  expect(saveButton).toHaveAttribute('data-inactive', 'true')
})

test('Users can be selected', async () => {
  const {user} = render(<AddUserToTeamButton {...props} />)
  const addMemberButton = screen.getByTestId('add-members-button')
  await user.click(addMemberButton)
  const selectAllCheckbox = screen.getByTestId('select-all-checkbox')
  const userOneCheckbox = screen.getByTestId('enterprise-member-0')
  const userTwoCheckbox = screen.getByTestId('enterprise-member-1')

  await user.click(userOneCheckbox)
  expect(selectAllCheckbox).toHaveAttribute('aria-checked', 'mixed')
  expect(userOneCheckbox).toHaveAttribute('aria-selected', 'true')
  expect(userTwoCheckbox).toHaveAttribute('aria-selected', 'false')
  await user.click(userTwoCheckbox)
  expect(selectAllCheckbox).toHaveAttribute('aria-checked', 'true')
  expect(userOneCheckbox).toHaveAttribute('aria-selected', 'true')
  expect(userTwoCheckbox).toHaveAttribute('aria-selected', 'true')
})

test('Users can be unselected', async () => {
  const {user} = render(<AddUserToTeamButton {...props} />)
  const addMemberButton = screen.getByTestId('add-members-button')
  await user.click(addMemberButton)
  const selectAllCheckbox = screen.getByTestId('select-all-checkbox')
  const userOneCheckbox = screen.getByTestId('enterprise-member-0')
  const userTwoCheckbox = screen.getByTestId('enterprise-member-1')
  await user.click(selectAllCheckbox)

  await user.click(userOneCheckbox)
  expect(selectAllCheckbox).toHaveAttribute('aria-checked', 'mixed')
  expect(userOneCheckbox).toHaveAttribute('aria-selected', 'false')
  expect(userTwoCheckbox).toHaveAttribute('aria-selected', 'true')
  await user.click(userTwoCheckbox)
  expect(selectAllCheckbox).toHaveAttribute('aria-checked', 'false')
  expect(userOneCheckbox).toHaveAttribute('aria-selected', 'false')
  expect(userTwoCheckbox).toHaveAttribute('aria-selected', 'false')
})

import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import type {User, UsersState} from '../user-types'
import {UserSelector, type UserSelectorProps} from '../UserSelector'
import {defaultUsersState, monalisa, octocat} from '../test-utils/mock-data'

const defaultProps: UserSelectorProps = {
  defaultText: 'All users',
  usersState: defaultUsersState,
  currentUser: undefined,
  hotKey: 'u',
}

const filterTestResponse: UsersState = {
  users: new Array(8).fill(0).map((_, i) => {
    return {
      name: `User name ${i}`,
      login: `user${i}`,
      primaryAvatarUrl: `http://alambic.github.localhost/avatars/u/${i}?s=80`,
      path: `/user${i}`,
    } as User
  }),
  error: false,
  loading: false,
}

test('Shows the default text in the expandable button', async () => {
  render(<UserSelector {...defaultProps} />)

  expect(screen.getByRole('button')).toHaveTextContent('All users')
})

test('Shows the current user in the expandable button', async () => {
  render(<UserSelector {...defaultProps} currentUser={monalisa} />)

  expect(screen.getByRole('button')).toHaveTextContent('monalisa')
})

test('Opens on click', async () => {
  const {user} = await render(<UserSelector {...defaultProps} />)
  const button = screen.getByRole('button')
  await user.click(button)

  expect(screen.getByText('monalisa')).toBeInTheDocument()
  expect(screen.getByText('Mona Lisa')).toBeInTheDocument()
  expect(screen.getByText('octocat')).toBeInTheDocument()
  expect(screen.getByText('Octo Cat')).toBeInTheDocument()
})

test('Shows a loading indicator while users are being fetched', async () => {
  const loadingResponse: UsersState = {
    users: [],
    error: false,
    loading: true,
  }
  const {user} = await render(<UserSelector {...defaultProps} usersState={loadingResponse} />)
  const button = screen.getByRole('button')
  await user.click(button)

  expect(screen.getByLabelText('Loading users...')).toBeInTheDocument()
  expect(screen.queryByText('Nothing to show')).not.toBeInTheDocument()
  expect(screen.queryByText('Filter on author')).not.toBeInTheDocument()
})

test('Shows an error when users cannot be fetched', async () => {
  const errorResponse: UsersState = {
    users: [],
    error: true,
    loading: false,
  }
  const {user} = await render(<UserSelector {...defaultProps} usersState={errorResponse} />)
  const button = screen.getByRole('button')
  await user.click(button)

  expect(screen.getByText('Could not load users')).toBeInTheDocument()
  expect(screen.queryByText('Nothing to show')).not.toBeInTheDocument()
  expect(screen.queryByText('Filter on author')).not.toBeInTheDocument()
})

test('Shows a zero state when no users are returned', async () => {
  const emptyResponse: UsersState = {
    users: [],
    error: false,
    loading: false,
  }
  const {user} = await render(<UserSelector {...defaultProps} usersState={emptyResponse} />)
  const button = screen.getByRole('button')
  await user.click(button)

  expect(screen.getByText('Nothing to show')).toBeInTheDocument()
})

test('Shows a zero state when no users are returned with showTypedInUser enabled', async () => {
  const emptyResponse: UsersState = {
    users: [],
    error: false,
    loading: false,
  }
  const {user} = await render(<UserSelector {...defaultProps} usersState={emptyResponse} showTypedInUser />)
  const button = screen.getByRole('button')
  await user.click(button)

  expect(screen.getByText('Nothing to show')).toBeInTheDocument()
})

test('Shows the people icon if no user selected', () => {
  render(<UserSelector {...defaultProps} />)
  expect(screen.queryByTestId('github-avatar')).not.toBeInTheDocument()
})

test('Shows the avatar if a current user is selected', () => {
  render(<UserSelector {...defaultProps} currentUser={octocat} />)
  expect(screen.getByTestId('github-avatar')).toBeInTheDocument()
})

test('Renders custom footer', async () => {
  const {user} = await render(
    <UserSelector
      {...defaultProps}
      renderCustomFooter={() => <div data-testid="user-picker-custom-footer">This is a custom footer</div>}
    />,
  )

  const button = screen.getByRole('button')
  await user.click(button)

  expect(screen.getByTestId('user-picker-custom-footer')).toHaveTextContent('This is a custom footer')
})

test('Virtualizes the list of results', async () => {
  const virtualizedResponse: UsersState = {
    users: new Array(1_000).fill(0).map((_, i) => {
      return {
        name: `User name ${i}`,
        login: `user${i}`,
        primaryAvatarUrl: `http://alambic.github.localhost/avatars/u/${i}?s=80`,
        path: `/user${i}`,
      } as User
    }),
    error: false,
    loading: false,
  }
  const {user} = await render(<UserSelector {...defaultProps} usersState={virtualizedResponse} />)

  const button = screen.getByRole('button')
  await user.click(button)

  // Since the virtualized list relies on DOM measurement, which is not
  // possible in jest tests, the best we can do is verify that not all of the
  // users appear in the DOM.
  expect(screen.queryAllByText('User name').length).toBeLessThan(25)
})

test('Filters the list of users based on the curent filter text', async () => {
  const {user} = await render(<UserSelector {...defaultProps} usersState={filterTestResponse} />)

  const button = screen.getByRole('button')
  await user.click(button)

  expect(screen.getAllByRole('menuitemradio')).toHaveLength(8)
  expect(screen.queryByText('Filter on author')).not.toBeInTheDocument()

  const input = screen.getByPlaceholderText('Find a user...')
  await user.click(input)

  // Expect 0 result experience shows with no matches
  await user.paste('none')
  expect(screen.getByText('Nothing to show')).toBeInTheDocument()
  expect(screen.queryByText('Filter on author')).not.toBeInTheDocument()

  // Expect 1 result
  await user.clear(input)
  await user.paste('4')
  expect(screen.getAllByRole('menuitemradio')).toHaveLength(1)
  expect(screen.queryByText('Filter on author')).not.toBeInTheDocument()

  // Expect all results when filter is cleared
  await user.clear(input)
  expect(screen.getAllByRole('menuitemradio')).toHaveLength(8)
  expect(screen.queryByText('Filter on author')).not.toBeInTheDocument()

  // Filter is case insensitive and searches login
  await user.clear(input)
  await user.paste('UsEr2')
  expect(screen.getAllByRole('menuitemradio')).toHaveLength(1)
  expect(screen.queryByText('Filter on author')).not.toBeInTheDocument()

  // Filter is case insensitive and searches name
  await user.clear(input)
  await user.paste('NaMe 7')
  expect(screen.getAllByRole('menuitemradio')).toHaveLength(1)
  expect(screen.queryByText('Filter on author')).not.toBeInTheDocument()

  // Expect all results when filter matches all
  await user.clear(input)
  await user.paste('User name')
  expect(screen.getAllByRole('menuitemradio')).toHaveLength(8)
  expect(screen.queryByText('Filter on author')).not.toBeInTheDocument()
})

test('Filters the list of users based on the curent filter text with selectable input when showTypedInUser', async () => {
  const {user} = await render(<UserSelector {...defaultProps} usersState={filterTestResponse} showTypedInUser />)

  const button = screen.getByRole('button')
  await user.click(button)

  expect(screen.getAllByRole('menuitemradio')).toHaveLength(8)
  expect(screen.queryByText('Filter on author')).not.toBeInTheDocument()
  expect(screen.queryByText('Nothing to show')).not.toBeInTheDocument()

  const input = screen.getByPlaceholderText('Find a user...')
  await user.click(input)

  // Expect 1 result - no matches + typed in user
  await user.paste('none')
  expect(screen.getAllByRole('menuitemradio')).toHaveLength(1)
  expect(screen.getByText('Filter on author')).toBeInTheDocument()
  expect(screen.queryByText('Nothing to show')).not.toBeInTheDocument()

  // Expect all results when filter is cleared and no typed in user
  await user.clear(input)
  expect(screen.getAllByRole('menuitemradio')).toHaveLength(8)
  expect(screen.queryByText('Filter on author')).not.toBeInTheDocument()
  expect(screen.queryByText('Nothing to show')).not.toBeInTheDocument()

  // if an exact login match - only return 1 result and do not show typed in user
  await user.clear(input)
  await user.paste('user7')
  expect(screen.getAllByRole('menuitemradio')).toHaveLength(1)
  expect(screen.queryByText('Filter on author')).not.toBeInTheDocument()
  expect(screen.queryByText('Nothing to show')).not.toBeInTheDocument()

  // Expect all results when filter matches all + typed in user
  await user.clear(input)
  await user.paste('User name')
  expect(screen.getAllByRole('menuitemradio')).toHaveLength(9)
  expect(screen.getByText('Filter on author')).toBeInTheDocument()
  expect(screen.queryByText('Nothing to show')).not.toBeInTheDocument()
})

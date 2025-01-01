import {screen} from '@testing-library/react'
import {render as reactRender} from '@github-ui/react-core/test-utils'
import {mockFetch} from '@github-ui/mock-fetch'
import {
  SecurityCampaignManagersSelect,
  type SecurityCampaignManagersSelectProps,
} from '../SecurityCampaignManagersSelect'
import {getTeam, getUser} from '../../test-utils/mock-data'
import type {SecurityManagersResult} from '../../hooks/use-campaign-managers-query'
import type {User} from '../../types/user'

const organizationLogin = 'github'
const campaignManagersPath = `/orgs/${organizationLogin}/security/campaigns/managers`

const defaultManager = getUser()
const defaultTeamManager = getTeam()

const manager = getUser({
  id: 3,
  login: 'octocat',
  name: null,
})
const manager1 = getUser({
  id: 4,
  login: 'hubot',
  name: null,
})

const teamManager = getTeam({
  id: 2,
  name: 'Last team on list',
  slug: 'z-last-team-manager',
})

const managers: User[] = [defaultManager, manager, manager1]

const render = (props?: Partial<SecurityCampaignManagersSelectProps>) =>
  reactRender(
    <SecurityCampaignManagersSelect
      users={[defaultManager]}
      onChangeUsers={jest.fn()}
      teams={[]}
      onChangeTeams={jest.fn()}
      organizationLogin={organizationLogin}
      maxManagers={10}
      {...props}
    />,
  )

beforeEach(() => {
  mockFetch.mockRoute(
    campaignManagersPath,
    {managers, teamManagers: [defaultTeamManager, teamManager]} satisfies SecurityManagersResult,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  // Mock the scrollTo method to prevent errors in the tests
  Object.defineProperty(window.Element.prototype, 'scrollTo', {
    value: jest.fn(),
    writable: true,
  })
})

test('the field shows placeholder text when no managers is selected', () => {
  render({
    users: [],
  })

  expect(screen.getByRole('button')).toHaveTextContent('Select manager')
})

test('the field shows the user login when a single manager is selected', () => {
  render({
    users: [manager],
  })

  expect(screen.getByRole('button')).toHaveTextContent(manager.login)
})

test('the field shows the user avatar when a single manager is selected', () => {
  render({
    users: [manager],
  })

  expect(screen.getByRole<HTMLImageElement>('img').src).toEqual(manager.avatarUrl)
})

test('the field shows the team slug when a single team is selected', () => {
  render({
    users: [],
    teams: [defaultTeamManager],
  })

  expect(screen.getByRole('button')).toHaveTextContent(defaultTeamManager.slug)
})

test('the field shows the team avatar when a single team is selected', () => {
  render({
    users: [],
    teams: [defaultTeamManager],
  })

  expect(screen.getByRole<HTMLImageElement>('img').src).toEqual(defaultTeamManager.avatarUrl)
})

test('the field shows multiple avatars when multiple managers are selected', () => {
  render({
    users: managers,
  })

  expect(screen.getAllByRole<HTMLImageElement>('img').length).toEqual(3)
})

test('the field shows "and 1 other" if two managers are selected', () => {
  render({
    users: [defaultManager, manager],
  })

  expect(screen.getByRole('button')).toHaveTextContent(`@${defaultManager.login} and 1 other`)
})

test('the field shows "and 2 others" if three managers are selected', () => {
  render({
    users: managers,
  })

  expect(screen.getByRole('button')).toHaveTextContent(`@${manager1.login} and 2 others`)
})

test('the field shows multiple team avatars when multiple teams have beens selected', () => {
  render({
    users: [],
    teams: [defaultTeamManager, teamManager],
  })

  expect(screen.getAllByRole<HTMLImageElement>('img').length).toEqual(2)
})

test('the field shows "and 1 other" if two teams are selected', () => {
  render({
    users: [],
    teams: [defaultTeamManager, teamManager],
  })

  expect(screen.getByRole('button')).toHaveTextContent(
    `@${defaultTeamManager.organizationLogin}/${defaultTeamManager.slug} and 1 other`,
  )
})

test('the field shows "and 2 others" if three teams are selected', () => {
  render({
    users: [],
    teams: [defaultTeamManager, teamManager, getTeam({id: 3, slug: 'team'})],
  })

  expect(screen.getByRole('button')).toHaveTextContent(
    `@${defaultTeamManager.organizationLogin}/${defaultTeamManager.slug} and 2 others`,
  )
})

test('the field allows adding a different user', async () => {
  const onChangeUsers = jest.fn()

  const {user} = render({
    onChangeUsers,
  })

  await user.click(screen.getByRole('button'))

  await user.click(
    screen.getByRole('option', {
      name: manager.login,
    }),
  )

  expect(onChangeUsers).toHaveBeenCalledTimes(1)
  expect(onChangeUsers).toHaveBeenCalledWith([defaultManager, manager])
})

test('the field allows adding a different team', async () => {
  const onChangeTeams = jest.fn()

  const {user} = render({
    onChangeTeams,
  })

  await user.click(screen.getByRole('button'))

  await user.click(
    screen.getByRole('option', {
      name: defaultTeamManager.slug,
    }),
  )

  expect(onChangeTeams).toHaveBeenCalledTimes(1)
  expect(onChangeTeams).toHaveBeenCalledWith([defaultTeamManager])
})

test('the field sorts the users by login', async () => {
  const onChangeUsers = jest.fn()

  const {user} = render({
    onChangeUsers,
    users: managers.slice(2),
  })

  await user.click(screen.getByRole('button'))

  await user.click(
    screen.getByRole('option', {
      name: defaultManager.login,
    }),
  )

  expect(onChangeUsers).toHaveBeenCalledTimes(1)
  expect(onChangeUsers).toHaveBeenCalledWith([managers[2], defaultManager])
})

test('the field sorts users and teams by login', async () => {
  const onChangeUsers = jest.fn()
  const onChangeTeams = jest.fn()

  const {user} = render({
    users: managers.slice(2),
    teams: [defaultTeamManager],
    onChangeUsers,
    onChangeTeams,
  })

  await user.click(screen.getByRole('button'))

  expect(screen.queryAllByRole('option').map(option => option.textContent)).toEqual([
    'hubot',
    'monalisaMona Lisa',
    'octocat',
    'teamTeam',
    'z-last-team-managerLast team on list',
  ])
})

test('the field allows removing a user', async () => {
  const onChangeUsers = jest.fn()

  const {user} = render({
    onChangeUsers,
    users: [defaultManager, manager],
  })

  await user.click(screen.getByRole('button'))

  await user.click(
    screen.getByRole('option', {
      name: defaultManager.login,
    }),
  )

  expect(onChangeUsers).toHaveBeenCalledTimes(1)
  expect(onChangeUsers).toHaveBeenCalledWith([manager])
})

test('the field allows removing a team', async () => {
  const onChangeTeams = jest.fn()

  const {user} = render({
    onChangeTeams,
    teams: [defaultTeamManager, teamManager],
  })

  await user.click(screen.getByRole('button'))

  await user.click(
    screen.getByRole('option', {
      name: defaultTeamManager.slug,
    }),
  )

  expect(onChangeTeams).toHaveBeenCalledTimes(1)
  expect(onChangeTeams).toHaveBeenCalledWith([teamManager])
})

test('the field allows removing the last user', async () => {
  const onChangeUsers = jest.fn()

  const {user} = render({
    onChangeUsers,
  })

  await user.click(screen.getByRole('button'))

  await user.click(
    screen.getByRole('option', {
      name: defaultManager.login,
    }),
  )

  expect(onChangeUsers).toHaveBeenCalledTimes(1)
  expect(onChangeUsers).toHaveBeenCalledWith([])
})

test('the field allows removing the last team', async () => {
  const onChangeTeams = jest.fn()

  const {user} = render({
    onChangeTeams,
    teams: [defaultTeamManager],
  })

  await user.click(screen.getByRole('button'))

  await user.click(
    screen.getByRole('option', {
      name: defaultTeamManager.slug,
    }),
  )

  expect(onChangeTeams).toHaveBeenCalledTimes(1)
  expect(onChangeTeams).toHaveBeenCalledWith([])
})

test('the field allows filtering by login', async () => {
  const {user} = render()

  await user.click(screen.getByRole('button'))

  expect(screen.queryAllByRole('option').length).toEqual(5)

  await user.type(screen.getByRole('textbox'), 'hu')

  expect(screen.queryAllByRole('option').length).toEqual(1)
  expect(screen.getByRole('option', {name: 'hubot'})).toBeInTheDocument()
})

test("the field shows the current value even if it's not in the response", async () => {
  const value = getUser({
    id: 5,
    login: 'not-in-response',
    name: null,
  })
  const teamNotInResponse = getTeam({
    id: 5,
    slug: 'not-in-response-team',
  })

  const {user} = render({
    users: [value],
    teams: [teamNotInResponse],
  })

  await user.click(screen.getByRole('button'))

  expect(screen.queryAllByRole('option').length).toEqual(7)
  expect(
    screen
      .queryAllByRole('option')
      .map(option => option.textContent)
      .sort(),
  ).toEqual([
    'hubot',
    'monalisaMona Lisa',
    'not-in-response',
    'not-in-response-teamTeam',
    'octocat',
    'teamTeam',
    'z-last-team-managerLast team on list',
  ])
})

test('the filter is cleared if the form is closed', async () => {
  const {user} = render()

  await user.click(screen.getByRole('button'))

  expect(screen.queryAllByRole('option').length).toEqual(5)

  await user.type(screen.getByRole('textbox'), 'hu')

  expect(screen.queryAllByRole('option').length).toEqual(1)
  expect(screen.getByRole('option', {name: 'hubot'})).toBeInTheDocument()

  await user.click(screen.getByRole('button', {name: 'Close'}))
  await user.click(screen.getByRole('button'))

  expect(screen.getByRole('textbox')).toHaveTextContent('')
  expect(screen.queryAllByRole('option').length).toEqual(5)
  expect(
    screen
      .queryAllByRole('option')
      .map(option => option.textContent)
      .sort(),
  ).toEqual(['hubot', 'monalisaMona Lisa', 'octocat', 'teamTeam', 'z-last-team-managerLast team on list'])
})

test('the field allows selecting a 10th user', async () => {
  const multipleManagers = [...Array(15).keys()].map(id => getUser({id, login: `user${String(id).padStart(2, '0')}`}))

  mockFetch.mockRoute(
    campaignManagersPath,
    {managers: multipleManagers, teamManagers: []} satisfies SecurityManagersResult,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const onChangeUsers = jest.fn()

  const {user} = render({
    onChangeUsers,
    users: multipleManagers.slice(0, 9),
  })

  await user.click(screen.getByRole('button'))

  await user.click(
    screen.getByRole('option', {
      name: multipleManagers[12]?.login,
    }),
  )

  expect(onChangeUsers).toHaveBeenCalledTimes(1)
  expect(onChangeUsers).toHaveBeenCalledWith([...multipleManagers.slice(0, 9), multipleManagers[12]])
})

test('the field allows selecting a 10th manager', async () => {
  const teamManagers = [...Array(15).keys()].map(id => getTeam({id, slug: `team${String(id).padStart(2, '0')}`}))

  mockFetch.mockRoute(campaignManagersPath, {managers: [], teamManagers} satisfies SecurityManagersResult, {
    headers: new Headers({
      'Content-Type': 'application/json',
    }),
  })

  const onChangeTeams = jest.fn()

  const {user} = render({
    onChangeTeams,
    users: [],
    teams: teamManagers.slice(0, 9),
  })

  await user.click(screen.getByRole('button'))

  await user.click(
    screen.getByRole('option', {
      name: teamManagers[12]?.slug,
    }),
  )

  expect(onChangeTeams).toHaveBeenCalledTimes(1)
  expect(onChangeTeams).toHaveBeenCalledWith([...teamManagers.slice(0, 9), teamManagers[12]])
})

test('the field does not allow selecting an 11th manager', async () => {
  const multipleManagers = [...Array(15).keys()].map(id => getUser({id, login: `user${String(id).padStart(2, '0')}`}))

  mockFetch.mockRoute(
    campaignManagersPath,
    {managers: multipleManagers, teamManagers: [defaultTeamManager, teamManager]} satisfies SecurityManagersResult,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const onChangeUsers = jest.fn()

  const {user} = render({
    onChangeUsers,
    users: multipleManagers.slice(0, 10),
  })

  await user.click(screen.getByRole('button'))

  expect(screen.getByText('You have reached the limit of 10 campaign managers.')).toBeInTheDocument()

  expect(
    screen.getByRole('option', {
      name: multipleManagers[12]?.login,
    }),
  ).toHaveAttribute('aria-disabled', 'true')
  expect(screen.getByRole('option', {name: defaultTeamManager.slug})).toHaveAttribute('aria-disabled', 'true')
})

test('the field renders the correct users when no team managers are returned', async () => {
  mockFetch.mockRoute(campaignManagersPath, {managers, teamManagers: null} satisfies SecurityManagersResult, {
    headers: new Headers({
      'Content-Type': 'application/json',
    }),
  })

  const onChangeUsers = jest.fn()

  const {user} = render({
    onChangeUsers,
    users: managers,
  })

  await user.click(screen.getByRole('button'))

  expect(screen.queryAllByRole('option').map(option => option.textContent)).toEqual([
    'hubot',
    'monalisaMona Lisa',
    'octocat',
  ])
})

test('managers are visible and disabled when disabled prop is true', async () => {
  const multipleManagers = [...Array(2).keys()].map(id => getUser({id, login: `user${String(id).padStart(2, '0')}`}))

  const mockApiCall = mockFetch.mockRoute(campaignManagersPath)
  expect(mockApiCall).not.toHaveBeenCalled()

  const {user} = render({
    users: multipleManagers,
    disabled: true,
  })

  await user.click(screen.getByRole('button'))

  expect(
    screen
      .queryAllByRole('option')
      .map(option => option.textContent)
      .sort(),
  ).toEqual(['user00Mona Lisa', 'user01Mona Lisa'])
  expect(screen.getByRole('option', {name: multipleManagers[0]?.login})).toHaveAttribute('aria-disabled', 'true')
  expect(screen.getByRole('option', {name: multipleManagers[1]?.login})).toHaveAttribute('aria-disabled', 'true')
})

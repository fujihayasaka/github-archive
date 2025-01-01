import {screen, within} from '@testing-library/react'
import {render as reactRender} from '@github-ui/react-core/test-utils'
import {CampaignManagersText, type CampaignManagersTextProps} from '../../components/CampaignManagersText'
import {getUser, getTeam} from '../../test-utils/mock-data'

const render = (props: Partial<CampaignManagersTextProps>) =>
  reactRender(<CampaignManagersText managers={[]} teamManagers={[]} {...props} />)

test('renders a single manager', () => {
  render({
    managers: [getUser()],
  })

  expect(screen.getByText('Managed by')).toBeInTheDocument()
  expect(screen.getByText('monalisa')).toBeInTheDocument()
  expect(screen.getByRole('link')).toHaveAttribute('href', '/monalisa')
})

test('renders two managers', () => {
  render({
    managers: [
      getUser({
        id: 1,
        login: 'monalisa',
      }),
      getUser({
        id: 2,
        login: 'octocat',
      }),
    ],
    teamManagers: [],
  })

  expect(screen.getByText('monalisa')).toBeInTheDocument()
  expect(screen.getByText('octocat')).toBeInTheDocument()
  expect(screen.getAllByRole('link').map(link => link.getAttribute('href'))).toEqual(['/monalisa', '/octocat'])
})

test('renders three managers', () => {
  render({
    managers: [
      getUser({
        id: 1,
        login: 'monalisa',
      }),
      getUser({
        id: 2,
        login: 'octocat',
      }),
      getUser({
        id: 3,
        login: 'octodemo',
      }),
    ],
  })

  expect(screen.getByText('monalisa')).toBeInTheDocument()
  expect(screen.getByText('and 2 others')).toBeInTheDocument()
  expect(screen.getByRole('link')).toHaveAttribute('href', '/monalisa')
  expect(screen.getByRole('button')).toBeInTheDocument()
})

test('renders four managers', () => {
  render({
    managers: [
      getUser({
        id: 1,
        login: 'monalisa',
      }),
      getUser({
        id: 2,
        login: 'octocat',
      }),
      getUser({
        id: 3,
        login: 'octodemo',
      }),
      getUser({
        id: 4,
        login: 'manager',
      }),
    ],
  })

  expect(screen.getByText('manager')).toBeInTheDocument()
  expect(screen.getByText('and 3 others')).toBeInTheDocument()
  expect(screen.getByRole('link')).toHaveAttribute('href', '/manager')
  expect(screen.getByRole('button')).toBeInTheDocument()
})

test('shows a dialog when clicking on the others link', async () => {
  const teamManager = getTeam()
  const {user} = render({
    managers: [
      getUser({
        id: 1,
        login: 'monalisa',
        name: 'Mona Lisa',
      }),
      getUser({
        id: 2,
        login: 'octocat',
        name: null,
      }),
      getUser({
        id: 3,
        login: 'octodemo',
        name: null,
      }),
      getUser({
        id: 4,
        login: 'manager',
        name: 'Security Manager',
      }),
    ],
    teamManagers: [teamManager],
  })

  await user.click(screen.getByText('and 4 others'))
  const dialog = screen.getByRole('dialog')
  expect(within(dialog).getByText('Campaign managers')).toBeInTheDocument()
  expect(
    within(dialog)
      .getAllByRole('listitem')
      .map(v => v.textContent),
  ).toEqual(['managerSecurity Manager', 'monalisaMona Lisa', 'octocat', 'octodemo', 'teamTeam'])
  expect(
    within(dialog)
      .getAllByRole('link')
      .map(v => v.getAttribute('href')),
  ).toEqual(['/manager', '/monalisa', '/octocat', '/octodemo', '/orgs/testOrg/teams/team'])
})

test('renders a single team manager with no user managers', () => {
  const teamManager = getTeam()
  render({
    teamManagers: [teamManager],
  })

  expect(screen.getByText('Managed by')).toBeInTheDocument()
  expect(screen.getByText(teamManager.slug)).toBeInTheDocument()
  expect(screen.getByRole('link')).toHaveAttribute('href', '/orgs/testOrg/teams/team')
})

test('renders two team managers with no user managers', () => {
  const teamManager1 = getTeam({slug: 'team-1'})
  const teamManager2 = getTeam({id: 2, name: 'Team 2', slug: 'team-2'})
  render({
    teamManagers: [teamManager1, teamManager2],
  })

  expect(screen.getByText(teamManager1.slug)).toBeInTheDocument()
  expect(screen.getByText(teamManager2.slug)).toBeInTheDocument()
  expect(screen.getAllByRole('link').map(link => link.getAttribute('href'))).toEqual([
    '/orgs/testOrg/teams/team-1',
    '/orgs/testOrg/teams/team-2',
  ])
})

test('render three team managers with no user managers', () => {
  const teamManager1 = getTeam()
  const teamManager2 = getTeam({id: 2, name: 'Team 2', slug: 'team-2'})
  const teamManager3 = getTeam({id: 3, name: 'Team 3', slug: 'team-3'})
  render({
    teamManagers: [teamManager1, teamManager2, teamManager3],
  })

  expect(screen.getByText(teamManager1.slug)).toBeInTheDocument()
  expect(screen.getByText('and 2 others')).toBeInTheDocument()
  expect(screen.getByRole('link')).toHaveAttribute('href', '/orgs/testOrg/teams/team')
  expect(screen.getByRole('button')).toBeInTheDocument()
})

test('renders combination of team and user managers', () => {
  const teamManager = getTeam()
  render({
    managers: [
      getUser({
        id: 1,
        login: 'monalisa',
        name: 'Mona Lisa',
      }),
    ],
    teamManagers: [teamManager],
  })

  expect(screen.getByText('monalisa')).toBeInTheDocument()
  expect(screen.getByText(teamManager.slug)).toBeInTheDocument()
  expect(screen.getAllByRole('link').map(link => link.getAttribute('href'))).toEqual([
    '/monalisa',
    '/orgs/testOrg/teams/team',
  ])
})

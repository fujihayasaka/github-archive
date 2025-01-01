import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {RepositorySecurityCampaignShow} from '../../routes/RepositorySecurityCampaignShow'
import {getRepositorySecurityCampaignShowRoutePayload} from '../../test-utils/mock-data'
import {getSecurityCampaign, getTeam, getUser} from '@github-ui/security-campaigns-shared/test-utils/mock-data'

test('Renders the campaign name and description', () => {
  const routePayload = getRepositorySecurityCampaignShowRoutePayload()
  render(<RepositorySecurityCampaignShow />, {
    routePayload,
  })
  expect(
    screen.getByRole('heading', {
      name: routePayload.campaign.name,
    }),
  ).toBeInTheDocument()
  expect(screen.getByText(routePayload.campaign.description)).toBeInTheDocument()
})

test('Renders a Feedback link', () => {
  const routePayload = getRepositorySecurityCampaignShowRoutePayload()
  render(<RepositorySecurityCampaignShow />, {
    routePayload,
  })

  expect(screen.getByText('Give feedback')).toBeInTheDocument()
})

test('Renders the campaign manager', () => {
  const routePayload = getRepositorySecurityCampaignShowRoutePayload()
  render(<RepositorySecurityCampaignShow />, {
    routePayload,
  })

  const expectedLogin = routePayload.campaign.managers[0]?.login ?? 'Unassigned'
  expect(screen.getByText(expectedLogin)).toBeInTheDocument()
})

test('Renders multiple campaign managers', () => {
  const routePayload = getRepositorySecurityCampaignShowRoutePayload({
    campaign: getSecurityCampaign({
      managers: [getUser({id: 1, login: 'monalisa'}), getUser({id: 2, login: 'octocat'})],
    }),
  })
  render(<RepositorySecurityCampaignShow />, {
    routePayload,
  })

  expect(screen.getByText('monalisa')).toBeInTheDocument()
  expect(screen.getByText('octocat')).toBeInTheDocument()
})

test('Renders a team manager', () => {
  const teamManager = getTeam()
  const routePayload = getRepositorySecurityCampaignShowRoutePayload({
    campaign: getSecurityCampaign({
      teamManagers: [teamManager],
    }),
  })
  render(<RepositorySecurityCampaignShow />, {
    routePayload,
  })

  expect(screen.getByText(teamManager.slug)).toBeInTheDocument()
})

test('Renders multiple team managers', () => {
  const teamManager1 = getTeam({id: 1, slug: 'team1'})
  const teamManager2 = getTeam({id: 2, slug: 'team2'})
  const routePayload = getRepositorySecurityCampaignShowRoutePayload({
    campaign: getSecurityCampaign({
      managers: [],
      teamManagers: [teamManager1, teamManager2],
    }),
  })
  render(<RepositorySecurityCampaignShow />, {
    routePayload,
  })

  expect(screen.getByText(teamManager1.slug)).toBeInTheDocument()
  expect(screen.getByText(teamManager2.slug)).toBeInTheDocument()
})

test('Renders a team manager and a user manager', () => {
  const teamManager = getTeam()
  const userManager = getUser()

  const routePayload = getRepositorySecurityCampaignShowRoutePayload({
    campaign: getSecurityCampaign({
      managers: [userManager],
      teamManagers: [teamManager],
    }),
  })

  render(<RepositorySecurityCampaignShow />, {
    routePayload,
  })

  expect(screen.getByText(userManager.login)).toBeInTheDocument()
  expect(screen.getByText(teamManager.slug)).toBeInTheDocument()
})

const hubberWarningText =
  'As a Hubber, you are able to view this page, but it would not be visible otherwise. Turn off site admin / employee mode (in the footer) to disable this feature.'

test('Renders a warning to GitHub staff when showHubberWarning is true', () => {
  const routePayload = getRepositorySecurityCampaignShowRoutePayload({
    showHubberWarning: true,
  })
  render(<RepositorySecurityCampaignShow />, {
    routePayload,
  })

  expect(screen.getByText(hubberWarningText)).toBeInTheDocument()
})

test('Does not render a warning to GitHub staff when showHubberWarning is false', () => {
  const routePayload = getRepositorySecurityCampaignShowRoutePayload({
    showHubberWarning: false,
  })
  render(<RepositorySecurityCampaignShow />, {
    routePayload,
  })

  expect(screen.queryByText(hubberWarningText)).not.toBeInTheDocument()
})

test('Renders contact link when a campaign has a contact link', () => {
  const routePayload = getRepositorySecurityCampaignShowRoutePayload()
  routePayload.campaign.contactLink = 'https://example.com'

  render(<RepositorySecurityCampaignShow />, {
    routePayload,
  })

  expect(screen.getByLabelText('Contact campaign manager')).toBeInTheDocument()
})

test('Does not render contact link when a campaign does not have a contact link', () => {
  const routePayload = getRepositorySecurityCampaignShowRoutePayload()
  routePayload.campaign.contactLink = null

  render(<RepositorySecurityCampaignShow />, {
    routePayload,
  })

  expect(screen.queryByLabelText('Contact campaign manager')).not.toBeInTheDocument()
})

test('Renders issue when a campaign has an issue', () => {
  const routePayload = getRepositorySecurityCampaignShowRoutePayload({
    issue: {
      number: 1,
      owner: 'github',
      repo: 'github',
      state: 'open',
      stateReason: '',
    },
  })

  render(<RepositorySecurityCampaignShow />, {
    routePayload,
  })

  expect(screen.getByText('and tracked on the issue')).toBeInTheDocument()
})

test('Does not render issue when a campaign has no issue', () => {
  const routePayload = getRepositorySecurityCampaignShowRoutePayload()

  render(<RepositorySecurityCampaignShow />, {
    routePayload,
  })

  expect(screen.queryByText('and tracked on the issue')).not.toBeInTheDocument()
})

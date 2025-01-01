import {screen} from '@testing-library/react'
import {render as reactRender} from '@github-ui/react-core/test-utils'
import {
  RepositorySecurityCampaignShow,
  type RepositorySecurityCampaignShowPayload,
} from '../../routes/RepositorySecurityCampaignShow'
import {
  getIssue,
  getRepositorySecurityCampaignShowRoutePayload,
  getSecurityCampaign,
  getTeam,
  getUser,
} from '../../test-utils/mock-data'
import {BannerProvider} from '@github-ui/role-assignments/banner-provider'

const defaultPayload = getRepositorySecurityCampaignShowRoutePayload()

type TestWrapperProps = {
  children: React.ReactNode
}

const render = (payload: Partial<RepositorySecurityCampaignShowPayload> = {}) =>
  reactRender(<RepositorySecurityCampaignShow />, {
    routePayload: {
      ...defaultPayload,
      ...payload,
    },
    wrapper: ({children}: TestWrapperProps) => {
      return <BannerProvider>{children}</BannerProvider>
    },
  })

test('Renders the campaign name and description', () => {
  render()
  expect(
    screen.getByRole('heading', {
      name: defaultPayload.campaign.name,
    }),
  ).toBeInTheDocument()
  expect(screen.getByText(defaultPayload.campaign.description)).toBeInTheDocument()
})

test('Renders a Feedback link', () => {
  render()

  expect(screen.getByText('Give feedback')).toBeInTheDocument()
})

test('Renders the campaign manager', () => {
  render()

  const expectedLogin = defaultPayload.campaign.managers[0]?.login ?? 'Unassigned'
  expect(screen.getByText(expectedLogin)).toBeInTheDocument()
  expect(screen.queryByText('Contact campaign managers')).not.toBeInTheDocument()
  expect(screen.getByText('Contact campaign manager')).toBeInTheDocument()
})

test('Renders multiple campaign managers', () => {
  render({
    campaign: getSecurityCampaign({
      managers: [getUser({id: 1, login: 'monalisa'}), getUser({id: 2, login: 'octocat'})],
    }),
  })

  expect(screen.getByText('monalisa')).toBeInTheDocument()
  expect(screen.getByText('octocat')).toBeInTheDocument()
  expect(screen.getByText('Contact campaign managers')).toBeInTheDocument()
})

test('Renders a team manager', () => {
  const teamManager = getTeam()

  render({
    campaign: getSecurityCampaign({
      teamManagers: [teamManager],
    }),
  })

  expect(screen.getByText(teamManager.slug)).toBeInTheDocument()
  expect(screen.getByText('Contact campaign managers')).toBeInTheDocument()
})

test('Renders multiple team managers', () => {
  const teamManager1 = getTeam({id: 1, slug: 'team1'})
  const teamManager2 = getTeam({id: 2, slug: 'team2'})

  render({
    campaign: getSecurityCampaign({
      managers: [],
      teamManagers: [teamManager1, teamManager2],
    }),
  })

  expect(screen.getByText(teamManager1.slug)).toBeInTheDocument()
  expect(screen.getByText(teamManager2.slug)).toBeInTheDocument()
})

test('Renders a team manager and a user manager', () => {
  const teamManager = getTeam()
  const userManager = getUser()

  render({
    campaign: getSecurityCampaign({
      managers: [userManager],
      teamManagers: [teamManager],
    }),
  })

  expect(screen.getByText(userManager.login)).toBeInTheDocument()
  expect(screen.getByText(teamManager.slug)).toBeInTheDocument()
})

const hubberWarningText =
  'As a Hubber, you are able to view this page, but it would not be visible otherwise. Turn off site admin / employee mode (in the footer) to disable this feature.'

test('Renders a warning to GitHub staff when showHubberWarning is true', () => {
  render({
    showHubberWarning: true,
  })

  expect(screen.getByText(hubberWarningText)).toBeInTheDocument()
})

test('Does not render a warning to GitHub staff when showHubberWarning is false', () => {
  render({
    showHubberWarning: false,
  })

  expect(screen.queryByText(hubberWarningText)).not.toBeInTheDocument()
})

test('Renders contact link when a campaign has a contact link', () => {
  render({
    campaign: getSecurityCampaign({
      contactLink: 'https://example.com',
    }),
  })

  expect(screen.getByLabelText('Contact campaign manager')).toBeInTheDocument()
})

test('Does not render contact link when a campaign does not have a contact link', () => {
  render({
    campaign: getSecurityCampaign({
      contactLink: null,
    }),
  })

  expect(screen.queryByLabelText('Contact campaign manager')).not.toBeInTheDocument()
})

test('Renders issue when a campaign has an issue', () => {
  render({
    issue: getIssue(),
  })

  expect(screen.getByText('and tracked on the issue')).toBeInTheDocument()
})

test('Does not render issue when a campaign has no issue', () => {
  render({
    issue: null,
  })

  expect(screen.queryByText('and tracked on the issue')).not.toBeInTheDocument()
})

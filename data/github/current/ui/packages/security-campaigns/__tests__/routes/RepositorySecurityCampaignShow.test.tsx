import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {RepositorySecurityCampaignShow} from '../../routes/RepositorySecurityCampaignShow'
import {getRepositorySecurityCampaignShowRoutePayload} from '../../test-utils/mock-data'

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

test('Renders a "Beta" label', () => {
  const routePayload = getRepositorySecurityCampaignShowRoutePayload()
  render(<RepositorySecurityCampaignShow />, {
    routePayload,
  })

  expect(screen.getByText('Beta')).toBeInTheDocument()
})

test('Renders the campaign manager', () => {
  const routePayload = getRepositorySecurityCampaignShowRoutePayload()
  render(<RepositorySecurityCampaignShow />, {
    routePayload,
  })

  const expectedLogin = routePayload.campaign.manager ? routePayload.campaign.manager.login : 'Unassigned'
  expect(screen.getByText(expectedLogin)).toBeInTheDocument()
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

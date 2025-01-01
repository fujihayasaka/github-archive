import {act, screen, waitFor, within} from '@testing-library/react'
import {setupExpectedAsyncErrorHandler} from '@github-ui/filter/test-utils'
import {getOrgSecurityCampaignShowRoutePayload} from '../../test-utils/mock-data'
import {getSecurityCampaign, getTeam, getUser} from '@github-ui/security-campaigns-shared/test-utils/mock-data'
import {OrgPublishedSecurityCampaign} from '../../components/OrgPublishedSecurityCampaign'
import {render} from '@github-ui/react-core/test-utils'
import {expectAnalyticsEvents} from '@github-ui/analytics-test-utils'
import {mockFetch} from '@github-ui/mock-fetch'
import {defaultQuery} from '../../hooks/use-alerts-params'
import type {CloseSecurityCampaignResponse} from '../../hooks/use-close-security-campaign-mutation'
import type {DeleteSecurityCampaignResponse} from '../../hooks/use-delete-security-campaign-mutation'
import type {UpdateSecurityCampaignResponse} from '../../hooks/use-update-security-campaign-mutation'
import type {GetAlertsGroupsResponse} from '../../types/get-alerts-groups-response'

const navigateFn = jest.fn()
const actionMenuTitle = 'Campaign options'
jest.mock('@github-ui/use-navigate', () => {
  return {
    useNavigate: () => navigateFn,
    useSearchParams: () => [new URLSearchParams(), jest.fn()],
  }
})

const originalWindowLocation = window.location
const mockReload = jest.fn()

beforeAll(() => {
  Object.defineProperty(window, 'location', {
    configurable: true,
    value: {...originalWindowLocation, reload: mockReload},
  })
})

afterAll(() => {
  Object.defineProperty(window, 'location', {configurable: true, value: originalWindowLocation})
})

afterEach(() => {
  jest.clearAllMocks()
})

jest.setTimeout(10_000)

test('Renders the breadcrumb when indexPageEnabled is true', async () => {
  setupExpectedAsyncErrorHandler()

  const routePayload = getOrgSecurityCampaignShowRoutePayload({
    campaign: getSecurityCampaign(),
    indexPageEnabled: true,
  })

  render(<OrgPublishedSecurityCampaign payload={routePayload} />)
  expect(
    screen.getByRole('link', {
      name: 'Campaigns',
    }),
  ).toHaveAttribute('href', '/orgs/github/security/campaigns')

  expect(
    screen.getByRole('heading', {
      name: routePayload.campaign.name,
    }),
  ).toBeInTheDocument()
})

test('Renders the breadcrumb when the campaign is closed', async () => {
  setupExpectedAsyncErrorHandler()

  const routePayload = getOrgSecurityCampaignShowRoutePayload({
    campaign: getSecurityCampaign({closedAt: Date.now().toString()}),
  })

  render(<OrgPublishedSecurityCampaign payload={routePayload} />)
  expect(
    screen.getByRole('link', {
      name: 'Closed campaigns',
    }),
  ).toBeInTheDocument()

  expect(
    screen.getByRole('heading', {
      name: routePayload.campaign.name,
    }),
  ).toBeInTheDocument()
})

test('Does not render the breadcrumb when the campaign is open', async () => {
  setupExpectedAsyncErrorHandler()

  const routePayload = getOrgSecurityCampaignShowRoutePayload()
  render(<OrgPublishedSecurityCampaign payload={routePayload} />)
  expect(
    screen.queryByRole('link', {
      name: 'Closed campaigns',
    }),
  ).not.toBeInTheDocument()
})

test('Renders the campaign name and description', async () => {
  setupExpectedAsyncErrorHandler()

  const routePayload = getOrgSecurityCampaignShowRoutePayload()
  render(<OrgPublishedSecurityCampaign payload={routePayload} />)
  expect(
    screen.getByRole('heading', {
      name: routePayload.campaign.name,
    }),
  ).toBeInTheDocument()
  expect(screen.getByText(routePayload.campaign.description)).toBeInTheDocument()
})

test('Renders a Feedback link', async () => {
  setupExpectedAsyncErrorHandler()

  const routePayload = getOrgSecurityCampaignShowRoutePayload()
  render(<OrgPublishedSecurityCampaign payload={routePayload} />)

  expect(screen.getByText('Give feedback')).toBeInTheDocument()
})

test('Renders the campaign manager', async () => {
  setupExpectedAsyncErrorHandler()

  const routePayload = getOrgSecurityCampaignShowRoutePayload()
  render(<OrgPublishedSecurityCampaign payload={routePayload} />)

  const expectedLogin = routePayload.campaign.managers[0]?.login ?? 'Unassigned'
  expect(screen.getByText(expectedLogin)).toBeInTheDocument()
})

test('Renders contact link when a campaign has a contact link', () => {
  setupExpectedAsyncErrorHandler()

  const routePayload = getOrgSecurityCampaignShowRoutePayload()
  routePayload.campaign.contactLink = 'https://example.com'
  render(<OrgPublishedSecurityCampaign payload={routePayload} />)

  expect(screen.getByLabelText('Contact campaign manager')).toBeInTheDocument()
})

test('Does not render contact link when a campaign does not have a contact link', () => {
  setupExpectedAsyncErrorHandler()

  const routePayload = getOrgSecurityCampaignShowRoutePayload()
  routePayload.campaign.contactLink = null
  render(<OrgPublishedSecurityCampaign payload={routePayload} />)

  expect(screen.queryByLabelText('Contact campaign manager')).not.toBeInTheDocument()
})

test('Renders multiple campaign managers', async () => {
  setupExpectedAsyncErrorHandler()

  const routePayload = getOrgSecurityCampaignShowRoutePayload({
    campaign: getSecurityCampaign({
      managers: [getUser({id: 1, login: 'monalisa'}), getUser({id: 2, login: 'octocat'})],
    }),
  })

  render(<OrgPublishedSecurityCampaign payload={routePayload} />)

  expect(screen.getByText('monalisa')).toBeInTheDocument()
  expect(screen.getByText('octocat')).toBeInTheDocument()
})

test('Renders a team manager', () => {
  setupExpectedAsyncErrorHandler()
  const teamManager = getTeam()

  const routePayload = getOrgSecurityCampaignShowRoutePayload({
    campaign: getSecurityCampaign({
      teamManagers: [teamManager],
    }),
  })

  render(<OrgPublishedSecurityCampaign payload={routePayload} />)

  expect(screen.getByText(teamManager.slug)).toBeInTheDocument()
})

test('Renders multiple team managers', () => {
  setupExpectedAsyncErrorHandler()
  const teamManager1 = getTeam({id: 1, slug: 'team1'})
  const teamManager2 = getTeam({id: 2, slug: 'team2'})

  const routePayload = getOrgSecurityCampaignShowRoutePayload({
    campaign: getSecurityCampaign({
      managers: [],
      teamManagers: [teamManager1, teamManager2],
    }),
  })

  render(<OrgPublishedSecurityCampaign payload={routePayload} />)

  expect(screen.getByText(teamManager1.slug)).toBeInTheDocument()
  expect(screen.getByText(teamManager2.slug)).toBeInTheDocument()
})

test('Renders a team manager and a user manager', () => {
  setupExpectedAsyncErrorHandler()
  const teamManager = getTeam()
  const userManager = getUser()

  const routePayload = getOrgSecurityCampaignShowRoutePayload({
    campaign: getSecurityCampaign({
      managers: [userManager],
      teamManagers: [teamManager],
    }),
  })

  render(<OrgPublishedSecurityCampaign payload={routePayload} />)

  expect(screen.getByText(userManager.login)).toBeInTheDocument()
  expect(screen.getByText(teamManager.slug)).toBeInTheDocument()
})

test('Renders the filter bar', async () => {
  setupExpectedAsyncErrorHandler()

  const routePayload = getOrgSecurityCampaignShowRoutePayload()
  render(<OrgPublishedSecurityCampaign payload={routePayload} />)

  expect(screen.getByRole('combobox', {name: 'Filter'})).toBeInTheDocument()
})

test('Sends request when changing the filter values', async () => {
  setupExpectedAsyncErrorHandler()
  const defaultGetAlertsResponse: GetAlertsGroupsResponse = {
    openCount: 0,
    closedCount: 0,
    nextCursor: 'cursornext',
    prevCursor: '',
    groups: [],
  }

  const routePayload = getOrgSecurityCampaignShowRoutePayload()
  const mockDefaultQuery = mockFetch.mockRoute(
    `/orgs/github/security/campaigns/5/alerts-groups?query=${encodeURIComponent(defaultQuery)}+${encodeURIComponent(
      'repo:1',
    )}&group=repository`,
    defaultGetAlertsResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const mockClosedQuery = mockFetch.mockRoute(
    `/orgs/github/security/campaigns/5/alerts-groups?query=${encodeURIComponent('is:closed')}+${encodeURIComponent(
      'repo:1',
    )}&group=repository`,
    defaultGetAlertsResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const {user} = render(<OrgPublishedSecurityCampaign payload={routePayload} />)

  await user.click(screen.getByRole('combobox', {name: 'Filter'}))
  await user.paste(' repo:1')
  await user.click(screen.getByRole('button', {name: 'Search'}))

  expect(mockDefaultQuery).toHaveBeenCalledTimes(1)

  await user.click(
    screen.getByRole('link', {
      name: /^Closed/,
    }),
  )
  expect(mockClosedQuery).toHaveBeenCalledTimes(1)
}, 20_000)

test('Navigates to the security overview page when the campaign is deleted', async () => {
  const routePayload = getOrgSecurityCampaignShowRoutePayload()

  const route = mockFetch.mockRoute(
    '/orgs/github/security/campaigns/5',
    {
      message: 'Campaign deleted successfully',
    } satisfies DeleteSecurityCampaignResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const {user} = render(<OrgPublishedSecurityCampaign payload={routePayload} />)

  const campaignMenuButton = screen.getByLabelText(actionMenuTitle)
  await user.click(campaignMenuButton)

  const deleteMenuItem = screen.getByText('Delete campaign')
  await user.click(deleteMenuItem)

  const dialog = screen.getByRole('dialog')

  expect(dialog).toHaveTextContent('Delete campaign?')

  const deleteConfirmationButton = within(dialog).getByRole('button', {name: 'Delete'})

  await user.click(deleteConfirmationButton)

  expect(route).toHaveBeenCalledWith(expect.any(String), expect.objectContaining({method: 'delete'}))
  expect(navigateFn).toHaveBeenCalledWith('/orgs/github/security/overview')
})

test('Shows an error when campaign deletion fails', async () => {
  const routePayload = getOrgSecurityCampaignShowRoutePayload()

  const route = mockFetch.mockRoute('/orgs/github/security/campaigns/5', 'invalid json', {
    ok: false,
    status: 500,
  })

  const {user} = render(<OrgPublishedSecurityCampaign payload={routePayload} />)

  const campaignMenuButton = screen.getByLabelText(actionMenuTitle)
  await user.click(campaignMenuButton)

  const deleteMenuItem = screen.getByText('Delete campaign')
  await user.click(deleteMenuItem)

  const dialog = screen.getByRole('dialog')

  const deleteConfirmationButton = within(dialog).getByRole('button', {name: 'Delete'})
  await user.click(deleteConfirmationButton)

  expect(route).toHaveBeenCalledTimes(1)
  expect(navigateFn).not.toHaveBeenCalled()

  expect(screen.getByText('Error deleting security campaign')).toBeInTheDocument()
  expect(dialog).not.toBeInTheDocument()
})

test('Closes delete confirmation dialog when cancel button is clicked', async () => {
  const routePayload = getOrgSecurityCampaignShowRoutePayload()

  const {user} = render(<OrgPublishedSecurityCampaign payload={routePayload} />)

  const campaignMenuButton = screen.getByLabelText(actionMenuTitle)
  await user.click(campaignMenuButton)

  const deleteMenuItem = screen.getByText('Delete campaign')
  await user.click(deleteMenuItem)

  const dialog = screen.getByRole('dialog')

  const cancelButton = within(dialog).getByRole('button', {name: 'Cancel'})
  await user.click(cancelButton)

  expect(dialog).not.toBeInTheDocument()
})

// Timeout has been increased to 20 seconds because this is an integration test
test('Allows updating the campaign name and description', async () => {
  const routePayload = getOrgSecurityCampaignShowRoutePayload()

  const route = mockFetch.mockRoute(
    '/orgs/github/security/campaigns/5',
    {
      message: 'Campaign updated successfully',
    } satisfies UpdateSecurityCampaignResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const {user} = render(<OrgPublishedSecurityCampaign payload={routePayload} />)

  const campaignMenuButton = screen.getByLabelText(actionMenuTitle)
  await user.click(campaignMenuButton)

  const editMenuItem = screen.getByText('Edit campaign')
  await user.click(editMenuItem)

  const newCampaignName = 'My new campaign name'
  await user.clear(getCampaignNameInput())
  await user.paste(newCampaignName)

  const newCampaignDescription = 'My new campaign description'
  await user.clear(getCampaignDescriptionInput())
  await user.paste(newCampaignDescription)

  const saveButton = screen.getByText('Save changes')
  await user.click(saveButton)

  expect(route).toHaveBeenCalledWith(
    expect.any(String),
    expect.objectContaining({
      method: 'put',
      body: JSON.stringify({
        campaign_name: newCampaignName,
        campaign_description: newCampaignDescription,
        campaign_due_date: routePayload.campaign.endsAt,
        campaign_managers: routePayload.campaign.managers.map(manager => manager.id),
        team_managers: [],
        campaign_contact_link: routePayload.campaign.contactLink,
      }),
    }),
  )

  // Name + description should be updated in the page
  expect(
    screen.getByRole('heading', {
      name: newCampaignName,
    }),
  ).toBeInTheDocument()
  expect(screen.getByText(newCampaignDescription)).toBeInTheDocument()

  expect(mockReload).toHaveBeenCalled()
}, 20_000)

test('Closing campaign calls close campaign endpoint', async () => {
  const routePayload = getOrgSecurityCampaignShowRoutePayload()

  const route = mockFetch.mockRoute(
    '/orgs/github/security/campaigns/5/close',
    {
      indexPageEnabled: true,
    } satisfies CloseSecurityCampaignResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const {user} = render(<OrgPublishedSecurityCampaign payload={routePayload} />)

  const campaignMenuButton = await screen.findByLabelText(actionMenuTitle)
  await user.click(campaignMenuButton)

  const closeCampaignMenuItem = await screen.findByText('Close campaign')
  act(() => {
    user.click(closeCampaignMenuItem)
  })

  await waitFor(() => expect(route).toHaveBeenCalledWith(expect.any(String), expect.objectContaining({method: 'post'})))
}, 20_000)

// Timeout has been increased to 20 seconds because this is an integration test
test('Reopening campaign calls reopen campaign endpoint', async () => {
  const routePayload = getOrgSecurityCampaignShowRoutePayload({
    campaign: getSecurityCampaign({closedAt: Date.now().toString()}),
  })

  const route = mockFetch.mockRoute(
    '/orgs/github/security/campaigns/5/reopen',
    {},
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const {user} = render(<OrgPublishedSecurityCampaign payload={routePayload} />)

  const campaignMenuButton = await screen.findByLabelText(actionMenuTitle)
  await user.click(campaignMenuButton)

  const closeCampaignMenuItem = await screen.findByText('Reopen campaign')
  await user.click(closeCampaignMenuItem)

  await waitFor(() => expect(route).toHaveBeenCalledWith(expect.any(String), expect.objectContaining({method: 'post'})))
}, 20_000)

test('Shows an error when closing campaign fails', async () => {
  const routePayload = getOrgSecurityCampaignShowRoutePayload()

  const route = mockFetch.mockRoute(
    '/orgs/github/security/campaigns/5/close',
    {message: 'Campaign is already closed'},
    {
      ok: false,
      status: 422,
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const {user} = render(<OrgPublishedSecurityCampaign payload={routePayload} />)

  const campaignMenuButton = await screen.findByLabelText(actionMenuTitle)
  await user.click(campaignMenuButton)

  const closeCampaignMenuItem = screen.getByText('Close campaign')
  await user.click(closeCampaignMenuItem)

  expect(route).toHaveBeenCalledTimes(1)
  expect(screen.getByText('Campaign is already closed')).toBeInTheDocument()
}, 20_000)

function getCampaignNameInput() {
  return screen.getByPlaceholderText('A short and descriptive name for this security campaign.')
}

function getCampaignDescriptionInput() {
  // Shorter placeholder text to make it easier to find the element in case it wraps
  return screen.getByPlaceholderText(/Let everybody know what this security campaign/)
}

test('Renders Repo limit warning', async () => {
  setupExpectedAsyncErrorHandler()

  const routePayload = getOrgSecurityCampaignShowRoutePayload({
    showIncompleteDataWarning: true,
  })
  render(<OrgPublishedSecurityCampaign payload={routePayload} />)

  expect(screen.getByTestId('incomplete-data-warning')).toBeInTheDocument()
})

test(`Send telemetry event when "Duplicate campaign" is clicked`, async () => {
  const mockCampaign = getSecurityCampaign({creationQuery: 'is:open'})
  const routePayload = getOrgSecurityCampaignShowRoutePayload({campaign: mockCampaign})

  const {user} = render(<OrgPublishedSecurityCampaign payload={routePayload} />)

  const campaignMenuButton = await screen.findByLabelText(actionMenuTitle)
  await user.click(campaignMenuButton)

  const duplicateCampaignMenuItem = await screen.findByText('Duplicate campaign')
  await user.click(duplicateCampaignMenuItem)

  expectAnalyticsEvents({
    type: 'analytics.click',
    data: {
      category: 'security_campaigns',
      action: 'duplicate',
      label: `source_campaign_id:${routePayload.campaign.id};org_id:1`,
    },
  })
})

test('Navigates to code scanning page with query and campaign number when duplicate campaign is clicked for open campaign and drafts disabled', async () => {
  const routePayload = {
    ...getOrgSecurityCampaignShowRoutePayload(),
    campaign: getSecurityCampaign({creationQuery: 'is:open', closedAt: null}),
  }

  const {user} = render(<OrgPublishedSecurityCampaign payload={routePayload} />)

  const campaignMenuButton = screen.getByLabelText(actionMenuTitle)
  await user.click(campaignMenuButton)

  const duplicateCampaignMenuItem = screen.getByText('Duplicate campaign')
  await user.click(duplicateCampaignMenuItem)

  expect(navigateFn).toHaveBeenCalledWith(
    '/orgs/github/security/alerts/code-scanning?query=is%3Aopen&source_campaign_number=5',
  )
})

test('Navigates to code scanning page with query and campaign number when duplicate campaign is clicked for closed campaign and drafts disabled', async () => {
  const routePayload = {
    ...getOrgSecurityCampaignShowRoutePayload(),
    campaign: getSecurityCampaign({creationQuery: 'is:open', closedAt: Date.now().toString()}),
  }

  const {user} = render(<OrgPublishedSecurityCampaign payload={routePayload} />)

  const campaignMenuButton = screen.getByLabelText(actionMenuTitle)
  await user.click(campaignMenuButton)

  const duplicateCampaignMenuItem = screen.getByText('Duplicate campaign')
  await user.click(duplicateCampaignMenuItem)

  expect(navigateFn).toHaveBeenCalledWith(
    '/orgs/github/security/alerts/code-scanning?query=is%3Aopen&source_campaign_number=5',
  )
})

test('Navigates to new campaign page when duplicate campaign is clicked for open campaign and drafts enabled', async () => {
  const routePayload = {
    ...getOrgSecurityCampaignShowRoutePayload(),
    campaign: getSecurityCampaign({creationQuery: 'is:open', closedAt: null}),
    draftCampaignsEnabled: true,
  }

  const {user} = render(<OrgPublishedSecurityCampaign payload={routePayload} />)

  const campaignMenuButton = screen.getByLabelText(actionMenuTitle)
  await user.click(campaignMenuButton)

  const duplicateCampaignMenuItem = screen.getByText('Duplicate campaign')
  await user.click(duplicateCampaignMenuItem)

  expect(navigateFn).toHaveBeenCalledWith(
    '/orgs/github/security/campaigns/new?query=is%3Aopen&source_campaign_number=5',
  )
})

test('Navigates to new campaign page when duplicate campaign is clicked for closed campaign and drafts enabled', async () => {
  const routePayload = {
    ...getOrgSecurityCampaignShowRoutePayload(),
    campaign: getSecurityCampaign({creationQuery: 'is:open', closedAt: Date.now().toString()}),
    draftCampaignsEnabled: true,
  }

  const {user} = render(<OrgPublishedSecurityCampaign payload={routePayload} />)

  const campaignMenuButton = screen.getByLabelText(actionMenuTitle)
  await user.click(campaignMenuButton)

  const duplicateCampaignMenuItem = screen.getByText('Duplicate campaign')
  await user.click(duplicateCampaignMenuItem)

  expect(navigateFn).toHaveBeenCalledWith(
    '/orgs/github/security/campaigns/new?query=is%3Aopen&source_campaign_number=5',
  )
})

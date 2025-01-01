import {act, screen, waitFor, within} from '@testing-library/react'
import {setupExpectedAsyncErrorHandler} from '@github-ui/filter/test-utils'
import {getOrgSecurityCampaignShowRoutePayload, getSecurityCampaign, getTeam, getUser} from '../../test-utils/mock-data'
import {OrgPublishedSecurityCampaign} from '../../components/OrgPublishedSecurityCampaign'
import {render as reactRender} from '@github-ui/react-core/test-utils'
import {expectAnalyticsEvents} from '@github-ui/analytics-test-utils'
// eslint-disable-next-line no-restricted-imports
import {mockFetch} from '@github-ui/mock-fetch'
import {defaultQuery} from '../../hooks/use-alerts-params'
import type {CloseSecurityCampaignResponse} from '../../hooks/use-close-security-campaign-mutation'
import type {DeleteSecurityCampaignResponse} from '../../hooks/use-delete-security-campaign-mutation'
import type {UpdateSecurityCampaignResponse} from '../../hooks/use-update-security-campaign-mutation'
import type {GetAlertsGroupsResponse} from '../../types/get-alerts-groups-response'
import type {OrgSecurityCampaignPayload} from '../../types/org-security-campaign-payload'

const navigateFn = jest.fn()
const actionMenuTitle = 'Campaign options'
jest.mock('@github-ui/use-navigate', () => {
  return {
    useSearchParams: () => [new URLSearchParams(), jest.fn()],
  }
})
jest.mock('@github-ui/role-assignments/banner-provider', () => ({
  useBannerContext: () => ({
    navigate: navigateFn,
  }),
}))

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

beforeEach(() => {
  setupExpectedAsyncErrorHandler()
})

afterEach(() => {
  jest.clearAllMocks()
})

jest.setTimeout(10_000)

const defaultPayload = getOrgSecurityCampaignShowRoutePayload()

const render = (payload: Partial<OrgSecurityCampaignPayload> = {}) =>
  reactRender(
    <OrgPublishedSecurityCampaign
      payload={{
        ...defaultPayload,
        ...payload,
      }}
    />,
  )

test('Renders the breadcrumb when indexPageEnabled is true', async () => {
  const routePayload = getOrgSecurityCampaignShowRoutePayload({
    campaign: getSecurityCampaign(),
    indexPageEnabled: true,
  })

  render({
    indexPageEnabled: true,
  })
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
  const campaign = getSecurityCampaign({closedAt: Date.now().toString()})

  render({
    campaign,
  })
  expect(
    screen.getByRole('link', {
      name: 'Closed campaigns',
    }),
  ).toBeInTheDocument()

  expect(
    screen.getByRole('heading', {
      name: campaign.name,
    }),
  ).toBeInTheDocument()
})

test('Does not render the breadcrumb when the campaign is open', async () => {
  render()
  expect(
    screen.queryByRole('link', {
      name: 'Closed campaigns',
    }),
  ).not.toBeInTheDocument()
})

test('Renders the campaign name and description', async () => {
  render()
  expect(
    screen.getByRole('heading', {
      name: defaultPayload.campaign.name,
    }),
  ).toBeInTheDocument()
  expect(screen.getByText(defaultPayload.campaign.description)).toBeInTheDocument()
})

test('Renders a Feedback link', async () => {
  render()

  expect(screen.getByText('Give feedback')).toBeInTheDocument()
})

test('Renders the campaign manager', async () => {
  render()

  const expectedLogin = defaultPayload.campaign.managers[0]?.login ?? 'Unassigned'
  expect(screen.getByText(expectedLogin)).toBeInTheDocument()
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

test('Renders multiple campaign managers', async () => {
  render({
    campaign: getSecurityCampaign({
      managers: [getUser({id: 1, login: 'monalisa'}), getUser({id: 2, login: 'octocat'})],
    }),
  })

  expect(screen.getByText('monalisa')).toBeInTheDocument()
  expect(screen.getByText('octocat')).toBeInTheDocument()
})

test('Renders a team manager', () => {
  const teamManager = getTeam()

  render({
    campaign: getSecurityCampaign({
      teamManagers: [teamManager],
    }),
  })

  expect(screen.getByText(teamManager.slug)).toBeInTheDocument()
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

test('Renders the filter bar', async () => {
  render()

  expect(screen.getByRole('combobox', {name: 'Filter'})).toBeInTheDocument()
})

test('Sends request when changing the filter values', async () => {
  const defaultGetAlertsResponse: GetAlertsGroupsResponse = {
    openCount: 0,
    closedCount: 0,
    nextCursor: 'cursornext',
    prevCursor: '',
    groups: [],
  }

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

  const {user} = render()

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
  const route = mockFetch.mockRoute('/orgs/github/security/campaigns/5', {} satisfies DeleteSecurityCampaignResponse, {
    headers: new Headers({
      'Content-Type': 'application/json',
    }),
  })

  const {user} = render()

  const campaignMenuButton = screen.getByLabelText(actionMenuTitle)
  await user.click(campaignMenuButton)

  const deleteMenuItem = screen.getByText('Delete campaign')
  await user.click(deleteMenuItem)

  const dialog = screen.getByRole('dialog')

  expect(dialog).toHaveTextContent('Delete campaign?')

  const deleteConfirmationButton = within(dialog).getByRole('button', {name: 'Delete'})

  await user.click(deleteConfirmationButton)

  expect(route).toHaveBeenCalledWith(expect.any(String), expect.objectContaining({method: 'delete'}))
  expect(navigateFn).toHaveBeenCalledWith('/orgs/github/security/overview', {reloadDocument: true}, undefined)
})

test('Shows an error when campaign deletion fails', async () => {
  const route = mockFetch.mockRoute('/orgs/github/security/campaigns/5', 'invalid json', {
    ok: false,
    status: 500,
  })

  const {user} = render()

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
  const {user} = render()

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
  const newCampaignName = 'My new campaign name'
  const newCampaignDescription = 'My new campaign description'

  const route = mockFetch.mockRoute(
    '/orgs/github/security/campaigns/5',
    {
      campaign: getSecurityCampaign({
        name: newCampaignName,
        description: newCampaignDescription,
      }),
    } satisfies UpdateSecurityCampaignResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const {user} = render()

  const campaignMenuButton = screen.getByLabelText(actionMenuTitle)
  await user.click(campaignMenuButton)

  const editMenuItem = screen.getByText('Edit campaign')
  await user.click(editMenuItem)

  await user.clear(getCampaignNameInput())
  await user.paste(newCampaignName)

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
        campaign_due_date: defaultPayload.campaign.endsAt,
        campaign_managers: defaultPayload.campaign.managers.map(manager => manager.id),
        team_managers: [],
        campaign_contact_link: defaultPayload.campaign.contactLink,
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
  const route = mockFetch.mockRoute(
    '/orgs/github/security/campaigns/5/close',
    {
      campaign: {
        ...defaultPayload.campaign,
        closedAt: Date.now().toString(),
      },
      indexPageEnabled: true,
    } satisfies CloseSecurityCampaignResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const {user} = render()

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
  const route = mockFetch.mockRoute(
    '/orgs/github/security/campaigns/5/reopen',
    {},
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const {user} = render({
    campaign: getSecurityCampaign({closedAt: Date.now().toString()}),
  })

  const campaignMenuButton = await screen.findByLabelText(actionMenuTitle)
  await user.click(campaignMenuButton)

  const closeCampaignMenuItem = await screen.findByText('Reopen campaign')
  await user.click(closeCampaignMenuItem)

  await waitFor(() => expect(route).toHaveBeenCalledWith(expect.any(String), expect.objectContaining({method: 'post'})))
}, 20_000)

test('Shows an error when closing campaign fails', async () => {
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

  const {user} = render()

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
  render({
    showIncompleteDataWarning: true,
  })

  expect(screen.getByTestId('incomplete-data-warning')).toBeInTheDocument()
})

test(`Send telemetry event when "Duplicate campaign" is clicked`, async () => {
  const campaign = getSecurityCampaign({creationQuery: 'is:open'})

  const {user} = render({
    campaign,
  })

  const campaignMenuButton = await screen.findByLabelText(actionMenuTitle)
  await user.click(campaignMenuButton)

  const duplicateCampaignMenuItem = await screen.findByText('Duplicate campaign')
  await user.click(duplicateCampaignMenuItem)

  expectAnalyticsEvents({
    type: 'analytics.click',
    data: {
      category: 'security_campaigns',
      action: 'duplicate',
      label: `source_campaign_id:${campaign.id};org_id:1`,
    },
  })
})

test('Navigates to new campaign page when duplicate campaign is clicked for open campaign', async () => {
  const {user} = render({
    campaign: getSecurityCampaign({creationQuery: 'is:open', closedAt: null}),
  })

  const campaignMenuButton = screen.getByLabelText(actionMenuTitle)
  await user.click(campaignMenuButton)

  const duplicateCampaignMenuItem = screen.getByText('Duplicate campaign')
  await user.click(duplicateCampaignMenuItem)

  expect(navigateFn).toHaveBeenCalledWith(
    '/orgs/github/security/campaigns/new?query=is%3Aopen&source_campaign_number=5',
  )
})

test('Navigates to new campaign page when duplicate campaign is clicked for closed campaign', async () => {
  const {user} = render({
    campaign: getSecurityCampaign({creationQuery: 'is:open', closedAt: Date.now().toString()}),
  })

  const campaignMenuButton = screen.getByLabelText(actionMenuTitle)
  await user.click(campaignMenuButton)

  const duplicateCampaignMenuItem = screen.getByText('Duplicate campaign')
  await user.click(duplicateCampaignMenuItem)

  expect(navigateFn).toHaveBeenCalledWith(
    '/orgs/github/security/campaigns/new?query=is%3Aopen&source_campaign_number=5',
  )
})

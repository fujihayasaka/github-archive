import {screen, waitFor, within} from '@testing-library/react'
import type {User as TestUser} from '@github-ui/react-core/test-utils'
import {render as reactRender} from '@github-ui/react-core/test-utils'
// eslint-disable-next-line no-restricted-imports
import {expectMockFetchCalledTimes, mockFetch} from '@github-ui/mock-fetch'
import {OrgSecurityCampaignNew, type OrgSecurityCampaignNewPayload} from '../../routes/OrgSecurityCampaignNew'
import {createSecurityCampaignAlert, getOrgSecurityCampaignNewRoutePayload} from '../../test-utils/mock-data'
import {setupExpectedAsyncErrorHandler} from '@github-ui/filter/test-utils'
import type {GetAlertsResponse} from '../../types/get-alerts-response'
import type {CreateDraftSecurityCampaignResponse} from '../../hooks/use-create-draft-security-campaign-mutation'

jest.setTimeout(10_000)

const navigateFn = jest.fn()
jest.mock('@github-ui/use-navigate', () => {
  return {
    useNavigate: () => navigateFn,
    useSearchParams: () => [new URLSearchParams(), jest.fn()],
  }
})

const defaultRoutePayload = getOrgSecurityCampaignNewRoutePayload()

const render = (routePayload: Partial<OrgSecurityCampaignNewPayload> = {}) =>
  reactRender(<OrgSecurityCampaignNew />, {
    routePayload: {
      ...defaultRoutePayload,
      ...routePayload,
    },
  })

const defaultGetAlertsResponse: GetAlertsResponse = {
  alerts: [
    createSecurityCampaignAlert({number: 1, title: 'Test alert 1'}),
    createSecurityCampaignAlert({number: 2, title: 'Test alert 2'}),
  ],
  alertCount: 2,
  openCount: 2,
  closedCount: 1,
  openWithLinksCount: 0,
  nextCursor: '',
  prevCursor: '',
}

beforeEach(() => {
  setupExpectedAsyncErrorHandler()
})

afterEach(() => {
  jest.clearAllMocks()
})

test('renders breadcrumbs', async () => {
  render()
  expect(
    screen.getByRole('link', {
      name: 'Campaigns',
    }),
  ).toHaveAttribute('href', '/orgs/github/security/campaigns')

  expect(screen.getByText('Select filters')).toBeInTheDocument()
})

test('Renders campaigns heading', async () => {
  render()
  expect(screen.getByRole('heading', {level: 2, name: 'Create a new campaign'})).toBeInTheDocument()
})

test('Renders a filter bar', async () => {
  render()

  expect(screen.getByRole('combobox', {name: 'Filter'})).toBeInTheDocument()
})

test('renders a blankslate', async () => {
  render()

  expect(screen.getByText('No filters defined')).toBeInTheDocument()

  expectMockFetchCalledTimes(/.*/, 0)
})

test('the save as button is inactive when no filter is entered', async () => {
  render()

  const saveButton = screen.getByRole('button', {name: 'Save as'})

  expect(saveButton).toHaveAttribute('data-inactive', 'true')
  expect(saveButton).toHaveAccessibleDescription('You have no filters defined')
})

test('opens the advanced filter dialog when clicking the "Add filters" button', async () => {
  const {user} = render()

  await user.click(
    screen.getByRole('button', {
      name: 'Add filters',
    }),
  )

  expect(screen.getByRole('dialog', {name: 'Advanced filters'})).toBeInTheDocument()
})

test('Sends request for closed alerts', async () => {
  const getAlertsResponse: GetAlertsResponse = {
    alerts: [],
    alertCount: 0,
    openCount: 0,
    openWithLinksCount: 0,
    closedCount: 0,
    nextCursor: 'cursornext',
    prevCursor: '',
  }

  const mockClosedQuery = mockFetch.mockRoute(
    `/orgs/github/security/alerts/code-scanning/alert-list?query=${encodeURIComponent('is:closed')}`,
    getAlertsResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const {user} = render()

  await user.click(screen.getByRole('combobox', {name: 'Filter'}))
  await user.paste('is:open')
  await user.click(screen.getByRole('button', {name: 'Search'}))

  await user.click(
    screen.getByRole('link', {
      name: /^Closed/,
    }),
  )
  expect(mockClosedQuery).toHaveBeenCalledTimes(1)
})

test('Sends request when entering a filter', async () => {
  const getAlertsResponse: GetAlertsResponse = {
    alerts: [],
    alertCount: 0,
    openCount: 0,
    openWithLinksCount: 0,
    closedCount: 5,
    nextCursor: 'cursornext',
    prevCursor: '',
  }

  const mockQuery = mockFetch.mockRoute(
    `/orgs/github/security/alerts/code-scanning/alert-list?query=${encodeURIComponent('is:open repo:repo1').replaceAll(
      '%20',
      '+',
    )}`,
    getAlertsResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const {user} = render()

  await user.click(screen.getByRole('combobox', {name: 'Filter'}))
  await user.paste('is:open repo:repo1')
  await user.click(screen.getByRole('button', {name: 'Search'}))

  await waitFor(() => {
    expect(screen.getByRole('link', {name: /^Closed/})).toHaveTextContent('5')
  })

  expect(mockQuery).toHaveBeenCalledTimes(1)
})

test('save dialog contains the expected fields', async () => {
  mockFetch.mockRoute(
    `/orgs/github/security/alerts/code-scanning/alert-list?query=${encodeURIComponent('is:open')}+${encodeURIComponent(
      'repo:repo1',
    )}`,
    defaultGetAlertsResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const {user} = render()

  await user.click(screen.getByRole('combobox', {name: 'Filter'}))
  await user.paste('is:open repo:repo1')
  await user.click(screen.getByRole('button', {name: 'Search'}))

  const dialog = await clickSaveAsDraftButton(user)

  expect(within(dialog).getByRole('textbox', {name: 'Campaign name *'})).toBeRequired()
  expect(within(dialog).getByRole('textbox', {name: 'Short description'})).not.toBeRequired()
  expect(
    within(dialog).getByRole('button', {
      name: `@${defaultRoutePayload.currentUser.login}, Campaign managers*`,
    }),
  ).toBeInTheDocument()
  expect(within(dialog).getByRole('textbox', {name: 'Contact link'})).not.toBeRequired()
})

test('can create a draft campaign with minimal information', async () => {
  mockFetch.mockRoute(
    `/orgs/github/security/alerts/code-scanning/alert-list?query=${encodeURIComponent('is:open')}+${encodeURIComponent(
      'autofix:supported',
    )}+${encodeURIComponent('autofilter:true')}`,
    defaultGetAlertsResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const mockCreate = mockFetch.mockRoute(
    `/orgs/github/security/campaigns/drafts`,
    {
      message: 'Campaign created',
      campaignNumber: 50,
    } satisfies CreateDraftSecurityCampaignResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const {user} = render()

  await user.click(screen.getByRole('combobox', {name: 'Filter'}))
  await user.paste('is:open autofix:supported autofilter:true')
  await user.click(screen.getByRole('button', {name: 'Search'}))

  const dialog = await clickSaveAsDraftButton(user)

  await enterCampaignName(user, dialog)
  await user.click(within(dialog).getByRole('button', {name: 'Save draft'}))

  expect(mockCreate).toHaveBeenCalledTimes(1)
  expect(mockCreate).toHaveBeenCalledWith(
    expect.any(String),
    expect.objectContaining({
      method: 'post',
      body: JSON.stringify({
        campaign_name: 'Test campaign',
        campaign_description: '',
        campaign_managers: [2],
        team_managers: [],
        campaign_contact_link: null,
        query: 'is:open autofix:supported autofilter:true',
      }),
    }),
  )
  expect(navigateFn).toHaveBeenCalledWith('/orgs/github/security/campaigns/50')
})

test('can create a draft campaign with manual information', async () => {
  mockFetch.mockRoute(
    `/orgs/github/security/alerts/code-scanning/alert-list?query=${encodeURIComponent('is:open')}+${encodeURIComponent(
      'repo:repo1',
    )}`,
    defaultGetAlertsResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const mockCreate = mockFetch.mockRoute(
    `/orgs/github/security/campaigns/drafts`,
    {
      message: 'Campaign created',
      campaignNumber: 50,
    } satisfies CreateDraftSecurityCampaignResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const {user} = render()

  await user.click(screen.getByRole('combobox', {name: 'Filter'}))
  await user.paste('is:open repo:repo1')
  await user.click(screen.getByRole('button', {name: 'Search'}))

  const dialog = await clickSaveAsDraftButton(user)

  await enterCampaignName(user, dialog)

  await user.click(within(dialog).getByRole('textbox', {name: 'Short description'}))
  await user.paste('This is my new draft campaign')

  await user.click(within(dialog).getByRole('textbox', {name: 'Contact link'}))
  await user.paste('https://github.com')

  await user.click(within(dialog).getByRole('button', {name: 'Save draft'}))

  expect(mockCreate).toHaveBeenCalledTimes(1)
  expect(mockCreate).toHaveBeenCalledWith(
    expect.any(String),
    expect.objectContaining({
      method: 'post',
      body: JSON.stringify({
        campaign_name: 'Test campaign',
        campaign_description: 'This is my new draft campaign',
        campaign_managers: [2],
        team_managers: [],
        campaign_contact_link: 'https://github.com',
        query: 'is:open repo:repo1',
      }),
    }),
  )
  expect(navigateFn).toHaveBeenCalledWith('/orgs/github/security/campaigns/50')
})

test('shows an error when draft campaign creation fails', async () => {
  mockFetch.mockRoute(
    `/orgs/github/security/alerts/code-scanning/alert-list?query=${encodeURIComponent('is:open')}+${encodeURIComponent(
      'repo:repo1',
    )}`,
    defaultGetAlertsResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const mockCreate = mockFetch.mockRoute(
    `/orgs/github/security/campaigns/drafts`,
    {
      message: 'Error creating draft campaign',
    },
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
      ok: false,
      status: 500,
    },
  )

  const {user} = render()

  await user.click(screen.getByRole('combobox', {name: 'Filter'}))
  await user.paste('is:open repo:repo1')
  await user.click(screen.getByRole('button', {name: 'Search'}))

  const dialog = await clickSaveAsDraftButton(user)

  await enterCampaignName(user, dialog)

  await user.click(within(dialog).getByRole('button', {name: 'Save draft'}))

  expect(mockCreate).toHaveBeenCalledTimes(1)
  expect(navigateFn).not.toHaveBeenCalled()
  expect(screen.getByText('Error creating draft campaign')).toBeVisible()
})

test('disables the save as draft button when max draft campaigns is reached', async () => {
  mockFetch.mockRoute(
    `/orgs/github/security/alerts/code-scanning/alert-list?query=${encodeURIComponent('is:open')}+${encodeURIComponent(
      'repo:repo1',
    )}`,
    defaultGetAlertsResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const {user} = render({
    orgDraftCampaignsCount: 10,
    maxDraftCampaigns: 10,
  })

  await user.click(screen.getByRole('combobox', {name: 'Filter'}))
  await user.paste('is:open repo:repo1')
  await user.click(screen.getByRole('button', {name: 'Search'}))

  await user.click(screen.getByRole('button', {name: 'Save as'}))
  expect(screen.getByRole('menuitem', {name: 'Draft campaign'})).toHaveAttribute('aria-disabled', 'true')
  expect(screen.getByText('Limit of 10 draft campaigns has been reached')).toBeVisible()
})

test('disables the save as draft button when max draft campaigns is reached with spam', async () => {
  mockFetch.mockRoute(
    `/orgs/github/security/alerts/code-scanning/alert-list?query=${encodeURIComponent('is:open')}+${encodeURIComponent(
      'repo:repo1',
    )}`,
    defaultGetAlertsResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const {user} = render({
    orgDraftCampaignsCount: 10,
    maxDraftCampaigns: 10,
    hasDraftSpam: true,
  })

  await user.click(screen.getByRole('combobox', {name: 'Filter'}))
  await user.paste('is:open repo:repo1')
  await user.click(screen.getByRole('button', {name: 'Search'}))

  await user.click(screen.getByRole('button', {name: 'Save as'}))
  expect(screen.getByRole('menuitem', {name: 'Draft campaign'})).toHaveAttribute('aria-disabled', 'true')
  expect(screen.getByText('Limit of 10 draft and spam campaigns has been reached')).toBeVisible()
})

test('prefills the dialog with pre-defined information', async () => {
  mockFetch.mockRoute(
    `/orgs/github/security/alerts/code-scanning/alert-list?query=${encodeURIComponent('is:open')}+${encodeURIComponent(
      'repo:repo1',
    )}`,
    defaultGetAlertsResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const {user} = render({
    campaignName: 'Test Template',
    campaignDescription: 'Test Template Description',
  })

  await user.click(screen.getByRole('combobox', {name: 'Filter'}))
  await user.paste('is:open repo:repo1')
  await user.click(screen.getByRole('button', {name: 'Search'}))

  const dialog = await clickSaveAsDraftButton(user)

  expect(within(dialog).getByRole('textbox', {name: 'Campaign name *'})).toHaveValue('Test Template')
  expect(within(dialog).getByRole('textbox', {name: 'Short description'})).toHaveValue('Test Template Description')
  expect(
    within(dialog).getByRole('button', {
      name: `@${defaultRoutePayload.currentUser.login}, Campaign managers*`,
    }),
  ).toBeInTheDocument()
})

test('can redirect to the publish page', async () => {
  mockFetch.mockRoute(
    `/orgs/github/security/alerts/code-scanning/alert-list?query=${encodeURIComponent('repo:repo1')}`,
    defaultGetAlertsResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const {user} = render()

  await user.click(screen.getByRole('combobox', {name: 'Filter'}))
  await user.paste('repo:repo1')
  await user.click(screen.getByRole('button', {name: 'Search'}))

  await clickSaveAsPublishedButton(user)

  expect(navigateFn).toHaveBeenCalledWith(
    `/orgs/github/security/campaigns/publish?query=${encodeURIComponent('repo:repo1')}`,
  )
})

test('redirects to the publish page with pre-defined information', async () => {
  mockFetch.mockRoute(
    `/orgs/github/security/alerts/code-scanning/alert-list?query=${encodeURIComponent('repo:repo1')}`,
    defaultGetAlertsResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const {user} = render({
    campaignName: 'Test Template',
    campaignDescription: 'Test Template Description',
  })

  await user.click(screen.getByRole('combobox', {name: 'Filter'}))
  await user.paste('repo:repo1')
  await user.click(screen.getByRole('button', {name: 'Search'}))

  await clickSaveAsPublishedButton(user)

  expect(navigateFn).toHaveBeenCalledWith(
    `/orgs/github/security/campaigns/publish?query=${encodeURIComponent(
      'repo:repo1',
    )}&campaign_name=${encodeURIComponent('Test Template')}&campaign_description=${encodeURIComponent(
      'Test Template Description',
    )}`,
  )
})

test('disables the save as published button when max published campaigns is reached', async () => {
  mockFetch.mockRoute(
    `/orgs/github/security/alerts/code-scanning/alert-list?query=${encodeURIComponent('repo:repo1')}`,
    defaultGetAlertsResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const {user} = render({
    orgOpenCampaignsCount: 10,
    maxOpenCampaigns: 10,
  })

  await user.click(screen.getByRole('combobox', {name: 'Filter'}))
  await user.paste('repo:repo1')
  await user.click(screen.getByRole('button', {name: 'Search'}))

  await user.click(screen.getByRole('button', {name: 'Save as'}))
  expect(screen.getByRole('menuitem', {name: 'Published campaign'})).toHaveAttribute('aria-disabled', 'true')
  expect(screen.getByText('Limit of 10 open campaigns has been reached')).toBeVisible()
})

test('disables the save as published button when max published campaigns is reached with spam', async () => {
  mockFetch.mockRoute(
    `/orgs/github/security/alerts/code-scanning/alert-list?query=${encodeURIComponent('repo:repo1')}`,
    defaultGetAlertsResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const {user} = render({
    orgOpenCampaignsCount: 10,
    maxOpenCampaigns: 10,
    hasOpenSpam: true,
  })

  await user.click(screen.getByRole('combobox', {name: 'Filter'}))
  await user.paste('repo:repo1')
  await user.click(screen.getByRole('button', {name: 'Search'}))

  await user.click(screen.getByRole('button', {name: 'Save as'}))
  expect(screen.getByRole('menuitem', {name: 'Published campaign'})).toHaveAttribute('aria-disabled', 'true')
  expect(screen.getByText('Limit of 10 open and spam campaigns has been reached')).toBeVisible()
})

test('navigates to publish campaign page when review and publish button is clicked on alerts limit reached dialog', async () => {
  const getAlertsResponse: GetAlertsResponse = {
    alerts: [],
    alertCount: 1001,
    openCount: 1000,
    closedCount: 1,
    openWithLinksCount: 0,
    nextCursor: '',
    prevCursor: '',
  }

  mockFetch.mockRoute(
    `/orgs/github/security/alerts/code-scanning/alert-list?query=${encodeURIComponent('is:open')}`,
    getAlertsResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const {user} = render()

  await user.click(screen.getByRole('combobox', {name: 'Filter'}))
  await user.paste('is:open')
  await user.click(screen.getByRole('button', {name: 'Search'}))
  await clickSaveAsPublishedButton(user)

  const dialog = await screen.findByRole('dialog')
  expect(dialog).toHaveTextContent('This looks like a big campaign')
  expect(dialog).toHaveTextContent(
    `Campaigns can include up to 1,000 alerts. The current list of alerts exceeds the campaign limit, consider editing your filters to reduce the list of alerts.`,
  )

  const proceedButton = within(dialog).getByRole('button', {name: 'Proceed'})
  await user.click(proceedButton)

  expect(navigateFn).toHaveBeenCalledWith(
    `/orgs/github/security/campaigns/publish?query=${encodeURIComponent('is:open')}`,
  )
})

test('cancels the alerts limit reached dialog when the cancel button is clicked', async () => {
  const getAlertsResponse: GetAlertsResponse = {
    alerts: [],
    alertCount: 1001,
    openCount: 1000,
    closedCount: 1,
    openWithLinksCount: 0,
    nextCursor: '',
    prevCursor: '',
  }

  mockFetch.mockRoute(
    `/orgs/github/security/alerts/code-scanning/alert-list?query=${encodeURIComponent('is:open')}`,
    getAlertsResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const {user} = render()

  await user.click(screen.getByRole('combobox', {name: 'Filter'}))
  await user.paste('is:open')
  await user.click(screen.getByRole('button', {name: 'Search'}))
  await clickSaveAsPublishedButton(user)

  const dialog = await screen.findByRole('dialog')
  expect(dialog).toHaveTextContent('This looks like a big campaign')

  const cancelButtonInDialog = within(dialog).getByRole('button', {name: 'Cancel'})
  await user.click(cancelButtonInDialog)

  expect(navigateFn).not.toHaveBeenCalled()
  expect(dialog).not.toBeVisible()
})

test('the save as button is inactive when no alerts match the filter', async () => {
  const getAlertsResponse: GetAlertsResponse = {
    alerts: [],
    alertCount: 0,
    openCount: 0,
    openWithLinksCount: 0,
    closedCount: 5,
    nextCursor: 'cursornext',
    prevCursor: '',
  }

  mockFetch.mockRoute(
    `/orgs/github/security/alerts/code-scanning/alert-list?query=${encodeURIComponent('is:open')}+${encodeURIComponent(
      'repo:repo1',
    )}`,
    getAlertsResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const {user} = render()

  await user.click(screen.getByRole('combobox', {name: 'Filter'}))
  await user.paste('is:open repo:repo1')
  await user.click(screen.getByRole('button', {name: 'Search'}))

  const saveButton = screen.getByRole('button', {name: 'Save as'})

  expect(saveButton).toHaveAttribute('data-inactive', 'true')
  expect(saveButton).toHaveAccessibleDescription('Could not find any alerts to include in the campaign')
})

async function clickSaveAsDraftButton(user: TestUser) {
  await user.click(screen.getByRole('button', {name: 'Save as'}))
  await user.click(screen.getByRole('menuitem', {name: 'Draft campaign'}))

  return screen.getByRole('dialog')
}

async function clickSaveAsPublishedButton(user: TestUser) {
  await user.click(screen.getByRole('button', {name: 'Save as'}))
  await user.click(screen.getByRole('menuitem', {name: 'Published campaign'}))
}

async function enterCampaignName(user: TestUser, dialog: HTMLElement, name = 'Test campaign') {
  await user.click(within(dialog).getByRole('textbox', {name: 'Campaign name *'}))
  await user.paste(name)
}

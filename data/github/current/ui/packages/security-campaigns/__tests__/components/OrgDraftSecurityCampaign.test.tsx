import {screen, within} from '@testing-library/react'
import type {User as TestUser} from '@github-ui/react-core/test-utils'
import {render} from '@github-ui/react-core/test-utils'
import {OrgDraftSecurityCampaign} from '../../components/OrgDraftSecurityCampaign'
import {createSecurityCampaignAlert, getOrgSecurityCampaignShowRoutePayload} from '../../test-utils/mock-data'
import {getSecurityCampaign} from '@github-ui/security-campaigns-shared/test-utils/mock-data'
import {setupExpectedAsyncErrorHandler} from '@github-ui/filter/test-utils'
import type {GetAlertsResponse} from '../../types/get-alerts-response'
import {mockFetch} from '@github-ui/mock-fetch'
import type {DeleteSecurityCampaignResponse} from '../../hooks/use-delete-security-campaign-mutation'

beforeEach(() => {
  setupExpectedAsyncErrorHandler()
})

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

test('It shows draft state label', async () => {
  const routePayload = {
    ...getOrgSecurityCampaignShowRoutePayload(),
    campaign: getSecurityCampaign({publishedAt: null}),
  }

  render(<OrgDraftSecurityCampaign payload={routePayload} />)

  const campaignHeader = screen.getByTestId('campaign-heading')
  const draftLabel = within(campaignHeader).getByText('Draft')

  expect(draftLabel).toBeInTheDocument()
})

test('Alerts are fetched from alert list endpoint', async () => {
  const routePayload = {
    ...getOrgSecurityCampaignShowRoutePayload(),
    campaign: getSecurityCampaign({creationQuery: 'is:open', publishedAt: null}),
  }
  const defaultGetAlertsResponse: GetAlertsResponse = {
    alerts: [
      createSecurityCampaignAlert({number: 1, title: 'Test alert 1'}),
      createSecurityCampaignAlert({number: 2, title: 'Test alert 2'}),
    ],
    openCount: 2,
    closedCount: 1,
    openWithLinksCount: 0,
    nextCursor: '',
    prevCursor: '',
  }

  mockFetch.mockRoute(
    `/orgs/github/security/alerts/code-scanning/alert-list?query=${encodeURIComponent('is:open')}+${encodeURIComponent(
      'repo:1',
    )}`,
    defaultGetAlertsResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const {user} = render(<OrgDraftSecurityCampaign payload={routePayload} />)

  await user.click(screen.getByRole('combobox', {name: 'Filter'}))
  await user.paste(' repo:1')
  await user.click(screen.getByRole('button', {name: 'Search'}))

  expect(screen.getByText('Test alert 1')).toBeInTheDocument()
  expect(screen.getByText('Test alert 2')).toBeInTheDocument()
})

test('Navigates to the campaigns drafts page when the draft campaign is deleted', async () => {
  const campaign = getSecurityCampaign({creationQuery: 'is:open', publishedAt: null})
  const routePayload = getOrgSecurityCampaignShowRoutePayload({
    campaign,
  })
  const deletePath = `/orgs/github/security/campaigns/drafts/${campaign.number}`

  const route = mockFetch.mockRoute(
    deletePath,
    {
      message: 'Campaign deleted successfully',
    } satisfies DeleteSecurityCampaignResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const {user} = render(<OrgDraftSecurityCampaign payload={routePayload} />)

  const campaignMenuButton = screen.getByLabelText(actionMenuTitle)
  await user.click(campaignMenuButton)

  const deleteMenuItem = screen.getByText('Delete draft')
  await user.click(deleteMenuItem)

  const dialog = screen.getByRole('dialog')

  const deleteConfirmationButton = within(dialog).getByRole('button', {name: 'Delete'})

  await user.click(deleteConfirmationButton)

  expect(route).toHaveBeenCalledWith(deletePath, expect.objectContaining({method: 'delete'}))
  expect(navigateFn).toHaveBeenCalledWith('/orgs/github/security/campaigns?state=draft')
})

describe('Edit campaign', () => {
  test('Shows edit dialog when edit button is clicked', async () => {
    const campaign = getSecurityCampaign({creationQuery: 'is:open', publishedAt: null})
    const routePayload = getOrgSecurityCampaignShowRoutePayload({
      campaign,
    })

    const {user} = render(<OrgDraftSecurityCampaign payload={routePayload} />)

    await clickEditMenuOption(user)

    const dialog = screen.getByRole('dialog')

    expect(dialog).toHaveTextContent('Edit draft campaign')
    expect(dialog).toHaveTextContent('Campaign name')
    expect(dialog).toHaveTextContent('Short description')
    expect(dialog).toHaveTextContent('Campaign managers')
    expect(dialog).toHaveTextContent('Contact link')
  })

  test('Edits campaign and closes dialog when save button is clicked after edit', async () => {
    const campaign = getSecurityCampaign({creationQuery: 'is:open', publishedAt: null})
    const routePayload = getOrgSecurityCampaignShowRoutePayload({
      campaign,
    })

    const editPath = `/orgs/github/security/campaigns/drafts/${campaign.number}`

    const route = mockFetch.mockRoute(
      editPath,
      {},
      {
        headers: new Headers({
          'Content-Type': 'application/json',
        }),
      },
    )

    const {user} = render(<OrgDraftSecurityCampaign payload={routePayload} />)

    await clickEditMenuOption(user)

    const dialog = screen.getByRole('dialog')

    const campaignNameInput = within(dialog).getByRole('textbox', {name: 'Campaign name *'})
    await user.click(campaignNameInput)
    await user.clear(campaignNameInput)
    await user.paste('Updated campaign name')

    const saveButton = within(dialog).getByRole('button', {name: 'Save draft'})
    await user.click(saveButton)

    expect(route).toHaveBeenCalledWith(
      editPath,
      expect.objectContaining({
        method: 'put',
        body: JSON.stringify({
          campaign_name: 'Updated campaign name',
          campaign_description: campaign.description,
          campaign_managers: campaign.managers.map(manager => manager.id),
          team_managers: campaign.teamManagers.map(manager => manager.id),
          campaign_contact_link: campaign.contactLink,
          query: campaign.creationQuery,
        }),
      }),
    )

    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })

  test('Shows an error when edit fails', async () => {
    const campaign = getSecurityCampaign({creationQuery: 'is:open', publishedAt: null})
    const routePayload = getOrgSecurityCampaignShowRoutePayload({
      campaign,
    })

    const editPath = `/orgs/github/security/campaigns/drafts/${campaign.number}`

    mockFetch.mockRoute(
      editPath,
      {},
      {
        ok: false,
        status: 500,
      },
    )

    const {user} = render(<OrgDraftSecurityCampaign payload={routePayload} />)

    await clickEditMenuOption(user)

    const dialog = screen.getByRole('dialog')

    const saveButton = within(dialog).getByRole('button', {name: 'Save draft'})
    await user.click(saveButton)

    expect(within(dialog).getByText('Sorry, something went wrong')).toBeInTheDocument()
  })

  test('Closes edit dialog when cancel button is clicked', async () => {
    const campaign = getSecurityCampaign({creationQuery: 'is:open', publishedAt: null})
    const routePayload = getOrgSecurityCampaignShowRoutePayload({
      campaign,
    })
    const editPath = `/orgs/github/security/campaigns/drafts/${campaign.number}`

    const route = mockFetch.mockRoute(
      editPath,
      {},
      {
        headers: new Headers({
          'Content-Type': 'application/json',
        }),
      },
    )

    const {user} = render(<OrgDraftSecurityCampaign payload={routePayload} />)

    await clickEditMenuOption(user)

    const dialog = screen.getByRole('dialog')

    const cancelButton = within(dialog).getByRole('button', {name: 'Cancel'})
    await user.click(cancelButton)

    expect(route).not.toHaveBeenCalled()

    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })
})

test('Shows an error when draft campaign deletion fails', async () => {
  const campaign = getSecurityCampaign({creationQuery: 'is:open', publishedAt: null})
  const routePayload = getOrgSecurityCampaignShowRoutePayload({
    campaign,
  })
  const deletePath = `/orgs/github/security/campaigns/drafts/${campaign.number}`

  const route = mockFetch.mockRoute(deletePath, 'invalid json', {
    ok: false,
    status: 500,
  })

  const {user} = render(<OrgDraftSecurityCampaign payload={routePayload} />)

  const campaignMenuButton = screen.getByLabelText(actionMenuTitle)
  await user.click(campaignMenuButton)

  const deleteMenuItem = screen.getByText('Delete draft')
  await user.click(deleteMenuItem)

  const dialog = screen.getByRole('dialog')

  const deleteConfirmationButton = within(dialog).getByRole('button', {name: 'Delete'})
  await user.click(deleteConfirmationButton)

  expect(route).toHaveBeenCalledTimes(1)
  expect(navigateFn).not.toHaveBeenCalled()

  expect(screen.getByText('Error deleting security campaign')).toBeInTheDocument()
  expect(dialog).not.toBeInTheDocument()
})

test('Closes delete confirmation dialog when cancel button is clicked on deleting a draft campaign', async () => {
  const campaign = getSecurityCampaign({creationQuery: 'is:open', publishedAt: null})
  const routePayload = getOrgSecurityCampaignShowRoutePayload({
    campaign,
  })

  const {user} = render(<OrgDraftSecurityCampaign payload={routePayload} />)

  const campaignMenuButton = screen.getByLabelText(actionMenuTitle)
  await user.click(campaignMenuButton)

  const deleteMenuItem = screen.getByText('Delete draft')
  await user.click(deleteMenuItem)

  const dialog = screen.getByRole('dialog')

  const cancelButton = within(dialog).getByRole('button', {name: 'Cancel'})
  await user.click(cancelButton)

  expect(dialog).not.toBeInTheDocument()
})

test('Shows delete confirmation dialog text for draft campaign deletion', async () => {
  const campaign = getSecurityCampaign({creationQuery: 'is:open', publishedAt: null})
  const routePayload = getOrgSecurityCampaignShowRoutePayload({
    campaign,
  })

  const {user} = render(<OrgDraftSecurityCampaign payload={routePayload} />)

  const campaignMenuButton = screen.getByLabelText(actionMenuTitle)
  await user.click(campaignMenuButton)

  const deleteMenuItem = screen.getByText('Delete draft')
  await user.click(deleteMenuItem)

  const dialog = screen.getByRole('dialog')

  expect(dialog).toHaveTextContent('Delete draft campaign?')
  expect(dialog).toHaveTextContent(`Are you sure you want to delete the draft campaign ${campaign.name}?`)
  expect(dialog).toHaveTextContent('This action cannot be undone.')
})

test('Progress metric shows the correct number of alerts', async () => {
  const routePayload = {
    ...getOrgSecurityCampaignShowRoutePayload(),
    campaign: getSecurityCampaign({
      creationQuery: 'is:open',
      publishedAt: null,
    }),
  }
  const defaultGetAlertsResponse: GetAlertsResponse = {
    alerts: [createSecurityCampaignAlert()],
    openCount: 1,
    closedCount: 1,
    openWithLinksCount: 0,
    nextCursor: '',
    prevCursor: '',
  }

  mockFetch.mockRoute(
    `/orgs/github/security/alerts/code-scanning/alert-list?query=${encodeURIComponent('is:open')}`,
    defaultGetAlertsResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  render(<OrgDraftSecurityCampaign payload={routePayload} />)

  const progressMetric = await within(screen.getByTestId('org-draft-security-campaign-metrics')).findByText('2')
  expect(progressMetric).toBeInTheDocument()
})

test('Progress metric shows warning if alerts exceed the limit for a draft campaign', async () => {
  const routePayload = {
    ...getOrgSecurityCampaignShowRoutePayload(),
    campaign: getSecurityCampaign({
      creationQuery: 'is:open',
      publishedAt: null,
    }),
  }
  const defaultGetAlertsResponse: GetAlertsResponse = {
    alerts: [],
    openCount: 1000,
    closedCount: 1,
    openWithLinksCount: 0,
    nextCursor: '',
    prevCursor: '',
  }

  mockFetch.mockRoute(
    `/orgs/github/security/alerts/code-scanning/alert-list?query=${encodeURIComponent('is:open')}`,
    defaultGetAlertsResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  render(<OrgDraftSecurityCampaign payload={routePayload} />)

  const warningMessage = await screen.findByText('Selected alerts exceeded')
  expect(warningMessage).toBeInTheDocument()
})

test('Status metric shows draft', async () => {
  const routePayload = {
    ...getOrgSecurityCampaignShowRoutePayload(),
    campaign: getSecurityCampaign({publishedAt: null}),
  }

  render(<OrgDraftSecurityCampaign payload={routePayload} />)

  expect(screen.getByText('The campaign is not published yet.')).toBeInTheDocument()
})

test('It shows the correct number of autofix-supported alerts', async () => {
  const routePayload = {
    ...getOrgSecurityCampaignShowRoutePayload(),
    campaign: getSecurityCampaign({
      creationQuery: 'is:open',
      publishedAt: null,
    }),
  }
  const defaultGetAlertsResponse: GetAlertsResponse = {
    alerts: [createSecurityCampaignAlert(), createSecurityCampaignAlert()],
    openCount: 2,
    closedCount: 1,
    openWithLinksCount: 0,
    nextCursor: '',
    prevCursor: '',
  }

  const params = new URLSearchParams()
  params.set('query', 'is:open autofix:supported')
  mockFetch.mockRoute(
    `/orgs/github/security/alerts/code-scanning/alert-list?${params.toString()}`,
    {...defaultGetAlertsResponse, openCount: 3, closedCount: 0},
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  render(<OrgDraftSecurityCampaign payload={routePayload} />)

  const autofixSupportedMetric = await within(screen.getByTestId('org-draft-security-campaign-metrics')).findByText('3')
  expect(autofixSupportedMetric).toBeInTheDocument()
})

test('Redirects to publish campaign page when review and publish button is clicked for a draft campaign', async () => {
  const campaign = getSecurityCampaign({creationQuery: 'is:open', publishedAt: null})
  const routePayload = getOrgSecurityCampaignShowRoutePayload({
    campaign,
  })
  const {user} = render(<OrgDraftSecurityCampaign payload={routePayload} />, {
    routePayload,
  })
  await user.click(screen.getByRole('button', {name: 'Review and publish campaign'}))

  expect(navigateFn).toHaveBeenCalledWith(`/orgs/github/security/campaigns/${campaign.number}/publish`)
})

test('Shows inactive review and publish campaign button when campaigns limit is reached', async () => {
  const campaign = getSecurityCampaign({creationQuery: 'is:open', publishedAt: null})
  const routePayload = getOrgSecurityCampaignShowRoutePayload({
    campaign,
    openOrgCampaignsCount: 10,
  })
  const {user} = render(<OrgDraftSecurityCampaign payload={routePayload} />, {
    routePayload,
  })
  const reviewAndPublishButton = await screen.findByRole('button', {name: 'Review and publish campaign'})
  expect(reviewAndPublishButton).toHaveAttribute('data-inactive', 'true')

  await user.hover(reviewAndPublishButton)
  const tooltip = screen.getByText(`Limit of ${routePayload.maxCampaigns} campaigns is reached`)
  expect(tooltip).toBeInTheDocument()
})

async function clickEditMenuOption(user: TestUser) {
  const campaignMenuButton = screen.getByLabelText(actionMenuTitle)
  await user.click(campaignMenuButton)

  const editMenuItem = screen.getByText('Edit draft')
  await user.click(editMenuItem)
}

import {screen, within} from '@testing-library/react'
import type {User as TestUser} from '@github-ui/react-core/test-utils'
import {render as reactRender} from '@github-ui/react-core/test-utils'
import {OrgDraftSecurityCampaign} from '../../components/OrgDraftSecurityCampaign'
import {
  createSecurityCampaignAlert,
  getOrgSecurityCampaignShowRoutePayload,
  getSecurityCampaign,
} from '../../test-utils/mock-data'
import {setupExpectedAsyncErrorHandler} from '@github-ui/filter/test-utils'
import type {GetAlertsResponse} from '../../types/get-alerts-response'
// eslint-disable-next-line no-restricted-imports
import {mockFetch} from '@github-ui/mock-fetch'
import type {DeleteSecurityCampaignResponse} from '../../hooks/use-delete-security-campaign-mutation'
import type {EditDraftSecurityCampaignResponse} from '../../hooks/use-edit-draft-security-campaign-mutation'
import type {OrgSecurityCampaignPayload} from '../../types/org-security-campaign-payload'

beforeEach(() => {
  setupExpectedAsyncErrorHandler()
})

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

afterEach(() => {
  jest.clearAllMocks()
})

jest.setTimeout(10_000)

const defaultPayload = {
  ...getOrgSecurityCampaignShowRoutePayload(),
  campaign: getSecurityCampaign({creationQuery: 'is:open', publishedAt: null}),
}

const render = (payload: Partial<OrgSecurityCampaignPayload> = {}) =>
  reactRender(
    <OrgDraftSecurityCampaign
      payload={{
        ...defaultPayload,
        ...payload,
      }}
    />,
  )

test('It shows draft state label', async () => {
  render()

  const campaignHeader = screen.getByTestId('campaign-heading')
  const draftLabel = within(campaignHeader).getByText('Draft')

  expect(draftLabel).toBeInTheDocument()
})

test('Alerts are fetched from alert list endpoint', async () => {
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

  const {user} = render()

  await user.click(screen.getByRole('combobox', {name: 'Filter'}))
  await user.paste(' repo:1')
  await user.click(screen.getByRole('button', {name: 'Search'}))

  expect(screen.getByText('Test alert 1')).toBeInTheDocument()
  expect(screen.getByText('Test alert 2')).toBeInTheDocument()
})

test('Navigates to the campaigns drafts page when the draft campaign is deleted', async () => {
  const deletePath = `/orgs/github/security/campaigns/drafts/${defaultPayload.campaign.number}`

  const route = mockFetch.mockRoute(deletePath, {} satisfies DeleteSecurityCampaignResponse, {
    headers: new Headers({
      'Content-Type': 'application/json',
    }),
  })

  const {user} = render()

  const campaignMenuButton = screen.getByLabelText(actionMenuTitle)
  await user.click(campaignMenuButton)

  const deleteMenuItem = screen.getByText('Delete draft')
  await user.click(deleteMenuItem)

  const dialog = screen.getByRole('dialog')

  const deleteConfirmationButton = within(dialog).getByRole('button', {name: 'Delete'})

  await user.click(deleteConfirmationButton)

  expect(route).toHaveBeenCalledWith(deletePath, expect.objectContaining({method: 'delete'}))
  expect(navigateFn).toHaveBeenCalledWith(
    '/orgs/github/security/campaigns?state=draft',
    {},
    {
      variant: 'success',
      message: 'The campaign User-controlled code injection was successfully deleted.',
    },
  )
})

describe('Edit campaign', () => {
  test('Shows edit dialog when edit button is clicked', async () => {
    const {user} = render()

    await clickEditMenuOption(user)

    const dialog = screen.getByRole('dialog')

    expect(dialog).toHaveTextContent('Edit draft campaign')
    expect(dialog).toHaveTextContent('Campaign name')
    expect(dialog).toHaveTextContent('Short description')
    expect(dialog).toHaveTextContent('Campaign managers')
    expect(dialog).toHaveTextContent('Contact link')
  })

  test('Edits campaign and closes dialog when save button is clicked after edit', async () => {
    const editPath = `/orgs/github/security/campaigns/drafts/${defaultPayload.campaign.number}`
    const newCampaignName = 'Updated campaign name'

    const route = mockFetch.mockRoute(
      editPath,
      {
        campaign: getSecurityCampaign({
          name: newCampaignName,
        }),
      } satisfies EditDraftSecurityCampaignResponse,
      {
        headers: new Headers({
          'Content-Type': 'application/json',
        }),
      },
    )

    const {user} = render()

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
          campaign_description: defaultPayload.campaign.description,
          campaign_managers: defaultPayload.campaign.managers.map(manager => manager.id),
          team_managers: defaultPayload.campaign.teamManagers.map(manager => manager.id),
          campaign_contact_link: defaultPayload.campaign.contactLink,
          query: defaultPayload.campaign.creationQuery,
        }),
      }),
    )

    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })

  test('Shows an error when edit fails', async () => {
    const editPath = `/orgs/github/security/campaigns/drafts/${defaultPayload.campaign.number}`

    mockFetch.mockRoute(
      editPath,
      {},
      {
        ok: false,
        status: 500,
      },
    )

    const {user} = render()

    await clickEditMenuOption(user)

    const dialog = screen.getByRole('dialog')

    const saveButton = within(dialog).getByRole('button', {name: 'Save draft'})
    await user.click(saveButton)

    expect(within(dialog).getByText('Sorry, something went wrong')).toBeInTheDocument()
  })

  test('Closes edit dialog when cancel button is clicked', async () => {
    const editPath = `/orgs/github/security/campaigns/drafts/${defaultPayload.campaign.number}`

    const route = mockFetch.mockRoute(
      editPath,
      {},
      {
        headers: new Headers({
          'Content-Type': 'application/json',
        }),
      },
    )

    const {user} = render()

    await clickEditMenuOption(user)

    const dialog = screen.getByRole('dialog')

    const cancelButton = within(dialog).getByRole('button', {name: 'Cancel'})
    await user.click(cancelButton)

    expect(route).not.toHaveBeenCalled()

    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })
})

test('Shows an error when draft campaign deletion fails', async () => {
  const deletePath = `/orgs/github/security/campaigns/drafts/${defaultPayload.campaign.number}`

  const route = mockFetch.mockRoute(deletePath, 'invalid json', {
    ok: false,
    status: 500,
  })

  const {user} = render()

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
  const {user} = render()

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
  const {user} = render()

  const campaignMenuButton = screen.getByLabelText(actionMenuTitle)
  await user.click(campaignMenuButton)

  const deleteMenuItem = screen.getByText('Delete draft')
  await user.click(deleteMenuItem)

  const dialog = screen.getByRole('dialog')

  expect(dialog).toHaveTextContent('Delete draft campaign?')
  expect(dialog).toHaveTextContent(
    `Are you sure you want to delete the draft campaign ${defaultPayload.campaign.name}?`,
  )
  expect(dialog).toHaveTextContent('This action cannot be undone.')
})

test('Progress metric shows the correct number of alerts', async () => {
  const defaultGetAlertsResponse: GetAlertsResponse = {
    alerts: [createSecurityCampaignAlert()],
    alertCount: 1,
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

  render()

  const progressMetric = await within(screen.getByTestId('org-draft-security-campaign-metrics')).findByText('1')
  expect(progressMetric).toBeInTheDocument()
})

test('Progress metric shows warning if alerts exceed the limit for a draft campaign', async () => {
  const defaultGetAlertsResponse: GetAlertsResponse = {
    alerts: [],
    alertCount: 1001,
    openCount: 1001,
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

  render()

  const warningMessage = await screen.findByText('Selected alerts exceeded')
  expect(warningMessage).toBeInTheDocument()
})

test('Status metric shows draft', async () => {
  render()

  expect(screen.getByText('The campaign is not published yet.')).toBeInTheDocument()
})

test('It shows the correct number of autofix-supported alerts', async () => {
  const defaultGetAlertsResponse: GetAlertsResponse = {
    alerts: [createSecurityCampaignAlert(), createSecurityCampaignAlert()],
    alertCount: 2,
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

  render()

  const autofixSupportedMetric = await within(screen.getByTestId('org-draft-security-campaign-metrics')).findByText('3')
  expect(autofixSupportedMetric).toBeInTheDocument()
})

test('Redirects to publish campaign page when review and publish button is clicked for a draft campaign', async () => {
  const defaultGetAlertsResponse: GetAlertsResponse = {
    alerts: [],
    alertCount: 10,
    openCount: 10,
    closedCount: 0,
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

  const {user} = render()
  await user.click(screen.getByRole('button', {name: 'Review and publish campaign'}))

  expect(navigateFn).toHaveBeenCalledWith(`/orgs/github/security/campaigns/${defaultPayload.campaign.number}/publish`)
})

test('Shows inactive review and publish campaign button when campaigns limit is reached', async () => {
  const defaultGetAlertsResponse: GetAlertsResponse = {
    alerts: [],
    alertCount: 1,
    openCount: 1,
    closedCount: 0,
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
  const {user} = render({
    openOrgCampaignsCount: 10,
  })
  const reviewAndPublishButton = await screen.findByRole('button', {name: 'Review and publish campaign'})
  expect(reviewAndPublishButton).toHaveAttribute('data-inactive', 'true')

  await user.hover(reviewAndPublishButton)
  const tooltip = screen.getByText(`Limit of ${defaultPayload.maxCampaigns} open campaigns is reached`)
  expect(tooltip).toBeInTheDocument()
})

test('Shows inactive review and publish campaign button when campaigns limit is reached with open spam', async () => {
  const defaultGetAlertsResponse: GetAlertsResponse = {
    alerts: [],
    alertCount: 1,
    openCount: 1,
    closedCount: 0,
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
  const {user} = render({
    openOrgCampaignsCount: 10,
    hasOpenSpam: true,
  })
  const reviewAndPublishButton = await screen.findByRole('button', {name: 'Review and publish campaign'})
  expect(reviewAndPublishButton).toHaveAttribute('data-inactive', 'true')

  await user.hover(reviewAndPublishButton)
  const tooltip = screen.getByText(`Limit of ${defaultPayload.maxCampaigns} open and spam campaigns is reached`)
  expect(tooltip).toBeInTheDocument()
})

test('Shows inactive review and publish campaign button when there are no alerts', async () => {
  const defaultGetAlertsResponse: GetAlertsResponse = {
    alerts: [],
    alertCount: 0,
    openCount: 0,
    closedCount: 0,
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

  const {user} = render({
    openOrgCampaignsCount: 1,
  })
  const reviewAndPublishButton = await screen.findByRole('button', {name: 'Review and publish campaign'})

  expect(reviewAndPublishButton).toHaveAttribute('data-inactive', 'true')
  await user.hover(reviewAndPublishButton)
  const tooltip = screen.getByText('Could not find any alerts to include in the campaign')
  expect(tooltip).toBeInTheDocument()
})

test('Shows inactive review and publish campaign button when filter is changed and not saved', async () => {
  const defaultGetAlertsResponse: GetAlertsResponse = {
    alerts: [],
    alertCount: 10,
    openCount: 10,
    closedCount: 0,
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
  const {user} = render({
    openOrgCampaignsCount: 1,
  })
  const filterInput = screen.getByRole('combobox', {name: 'Filter'})
  await user.click(filterInput)
  await user.paste('tool:codeql')

  const reviewAndPublishButton = await screen.findByRole('button', {name: 'Review and publish campaign'})
  expect(reviewAndPublishButton).toHaveAttribute('data-inactive', 'true')

  await user.hover(reviewAndPublishButton)
  const tooltip = screen.getByText('Filter query has changed. Please discard or save the changes before publishing')
  expect(tooltip).toBeInTheDocument()
})

test('Navigates to publish campaign page when review and publish button is clicked on alerts limit reached dialog', async () => {
  const defaultGetAlertsResponse: GetAlertsResponse = {
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
    defaultGetAlertsResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const {user} = render()

  const reviewAndPublishButton = screen.getByRole('button', {name: 'Review and publish campaign'})
  await user.click(reviewAndPublishButton)

  const dialog = await screen.findByRole('dialog')
  expect(dialog).toHaveTextContent('This looks like a big campaign')
  expect(dialog).toHaveTextContent(
    `Campaigns can include up to 1,000 alerts. The current list of alerts exceeds the campaign limit, consider editing your filters to reduce the list of alerts.`,
  )

  const proceedButton = within(dialog).getByRole('button', {name: 'Proceed'})
  await user.click(proceedButton)

  expect(navigateFn).toHaveBeenCalledWith(`/orgs/github/security/campaigns/${defaultPayload.campaign.number}/publish`)
})

test('Cancels the alerts limit reached dialog when the cancel button is clicked', async () => {
  const defaultGetAlertsResponse: GetAlertsResponse = {
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
    defaultGetAlertsResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const {user} = render()

  const reviewAndPublishButton = screen.getByRole('button', {name: 'Review and publish campaign'})
  await user.click(reviewAndPublishButton)

  const dialog = await screen.findByRole('dialog')
  const cancelButton = within(dialog).getByRole('button', {name: 'Cancel'})
  await user.click(cancelButton)

  expect(navigateFn).not.toHaveBeenCalled()
  expect(dialog).not.toBeInTheDocument()
})

async function clickEditMenuOption(user: TestUser) {
  const campaignMenuButton = screen.getByLabelText(actionMenuTitle)
  await user.click(campaignMenuButton)

  const editMenuItem = screen.getByText('Edit draft')
  await user.click(editMenuItem)
}

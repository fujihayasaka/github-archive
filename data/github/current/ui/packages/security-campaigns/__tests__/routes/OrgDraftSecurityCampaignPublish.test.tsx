import {screen, within} from '@testing-library/react'
import {render as reactRender, type User} from '@github-ui/react-core/test-utils'
// eslint-disable-next-line no-restricted-imports
import {mockFetch} from '@github-ui/mock-fetch'
import {
  createRepository,
  getDraftSecurityCampaign,
  getOrgDraftSecurityCampaignPublishRoutePayload,
  getTeam,
  getUser,
} from '../../test-utils/mock-data'
import {
  OrgDraftSecurityCampaignPublish,
  type OrgDraftSecurityCampaignPublishPayload,
} from '../../routes/OrgDraftSecurityCampaignPublish'
import type {PublishDraftSecurityCampaignResponse} from '../../hooks/use-publish-draft-security-campaign-mutation'
import type {AlertsSummaryResponse} from '../../hooks/use-alerts-summary-query'

jest.setTimeout(10_000)

const navigateFn = jest.fn()
jest.mock('@github-ui/role-assignments/banner-provider', () => ({
  useBannerContext: () => ({
    navigate: navigateFn,
  }),
}))

const defaultRoutePayload = getOrgDraftSecurityCampaignPublishRoutePayload()

const render = (routePayload: Partial<OrgDraftSecurityCampaignPublishPayload> = {}) =>
  reactRender(<OrgDraftSecurityCampaignPublish />, {
    routePayload: {
      ...defaultRoutePayload,
      ...routePayload,
    },
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
  expect(
    screen.getByRole('link', {
      name: defaultRoutePayload.campaign.name,
    }),
  ).toHaveAttribute('href', '/orgs/github/security/campaigns/5')

  expect(screen.getByText('Publish')).toBeInTheDocument()
})

test('renders heading', async () => {
  render()
  expect(screen.getByRole('heading', {level: 2, name: 'Publish campaign'})).toBeInTheDocument()
})

test('renders all fields with data from full campaign', async () => {
  render({
    campaign: getDraftSecurityCampaign({
      managers: [getUser()],
      teamManagers: [getTeam()],
    }),
  })

  expect(getNameInput()).toHaveValue(defaultRoutePayload.campaign.name)
  expect(getDescriptionInput()).toHaveValue(defaultRoutePayload.campaign.description)
  expect(
    screen.getByRole('button', {
      name: /Campaign managers/,
    }),
  ).toHaveTextContent(`@${defaultRoutePayload.campaign.managers[0]?.login} and 1 other`)
  expect(getContactLinkInput()).toHaveValue(defaultRoutePayload.campaign.contactLink)

  expect(screen.getByRole('button', {name: 'Publish campaign'})).toBeDisabled()
})

test('renders all fields with data from minimal campaign', async () => {
  render({
    campaign: getDraftSecurityCampaign({
      description: null,
      contactLink: null,
    }),
  })

  expect(getNameInput()).toHaveValue(defaultRoutePayload.campaign.name)
  expect(getDescriptionInput()).toHaveValue('')
  expect(
    screen.getByRole('button', {
      name: /Campaign managers/,
    }),
  ).toHaveTextContent(`@${defaultRoutePayload.campaign.managers[0]?.login}`)
  expect(getContactLinkInput()).toHaveValue('')
})

test('can publish a campaign with minimal information', async () => {
  const route = mockFetch.mockRoute(
    '/orgs/github/security/campaigns/drafts/5/publish',
    {
      campaignNumber: 5,
    } satisfies PublishDraftSecurityCampaignResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const {user} = render({
    campaign: getDraftSecurityCampaign({
      description: null,
      contactLink: null,
    }),
  })

  await user.click(getDescriptionInput())
  await user.paste('This is a short description')

  await selectDueDate(user)

  const publishButton = screen.getByRole('button', {name: 'Publish campaign'})
  expect(publishButton).not.toBeDisabled()

  await user.click(publishButton)

  const expectedDueDate = new Date()
  expectedDueDate.setDate(1)
  expectedDueDate.setMonth(expectedDueDate.getMonth() + 1)
  expectedDueDate.setHours(0, 0, 0, 0)

  expect(route).toHaveBeenCalledTimes(1)
  expect(route).toHaveBeenCalledWith(
    expect.any(String),
    expect.objectContaining({
      method: 'post',
      body: JSON.stringify({
        campaign_name: 'User-controlled code injection',
        campaign_description: 'This is a short description',
        campaign_due_date: expectedDueDate.toISOString(),
        campaign_managers: [2],
        team_managers: [],
        campaign_contact_link: null,
        campaign_generate_autofix_pull_requests: false,
        campaign_generate_issues: false,
        query: 'is:open',
      }),
    }),
  )

  expect(navigateFn).toHaveBeenCalledWith(
    '/orgs/github/security/campaigns/5',
    {
      reloadDocument: true,
    },
    undefined,
  )
})

test('can publish a campaign with full information', async () => {
  mockFetch.mockRoute(
    `/orgs/github/security/campaigns/alerts/summary?query=${encodeURIComponent('is:open')}`,
    {
      repositories: [
        {
          repository: createRepository(),
          alertCount: 5,
          issuesEnabled: true,
        },
        {
          repository: createRepository(),
          alertCount: 10,
          issuesEnabled: false,
        },
        {
          repository: createRepository(),
          alertCount: 2,
          issuesEnabled: true,
        },
        {
          repository: createRepository(),
          alertCount: 2,
          issuesEnabled: true,
        },
      ],
    } satisfies AlertsSummaryResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const route = mockFetch.mockRoute(
    '/orgs/github/security/campaigns/drafts/5/publish',
    {
      campaignNumber: 5,
    } satisfies PublishDraftSecurityCampaignResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const {user} = render({
    campaign: getDraftSecurityCampaign({
      description: null,
      contactLink: null,
    }),
  })

  await user.click(getDescriptionInput())
  await user.paste('This is a short description')

  await user.click(getContactLinkInput())
  await user.paste('https://github.com')

  await user.click(screen.getByRole('checkbox', {name: 'Create issues for 3 repositories in this campaign'}))
  await user.click(screen.getByRole('checkbox', {name: 'Generate up to 4 pull requests using Copilot Autofix'}))

  await selectDueDate(user)

  const publishButton = screen.getByRole('button', {name: 'Publish campaign'})
  expect(publishButton).not.toBeDisabled()

  await user.click(publishButton)

  const expectedDueDate = new Date()
  expectedDueDate.setDate(1)
  expectedDueDate.setMonth(expectedDueDate.getMonth() + 1)
  expectedDueDate.setHours(0, 0, 0, 0)

  expect(route).toHaveBeenCalledTimes(1)
  expect(route).toHaveBeenCalledWith(
    expect.any(String),
    expect.objectContaining({
      method: 'post',
      body: JSON.stringify({
        campaign_name: 'User-controlled code injection',
        campaign_description: 'This is a short description',
        campaign_due_date: expectedDueDate.toISOString(),
        campaign_managers: [2],
        team_managers: [],
        campaign_contact_link: 'https://github.com',
        campaign_generate_autofix_pull_requests: true,
        campaign_generate_issues: true,
        query: 'is:open',
      }),
    }),
  )

  expect(navigateFn).toHaveBeenCalledWith('/orgs/github/security/campaigns/5', {reloadDocument: true}, undefined)
})

test('shows the warning banner if limit of open campaigns is reached', () => {
  render({orgOpenCampaignsCount: 10, maxOpenCampaigns: 10})

  const warningBanner = screen.getByTestId('warning-banner')
  expect(warningBanner).toBeInTheDocument()
  expect(warningBanner).toHaveTextContent(
    'This organization has reached the limit of 10 active campaigns. To create a new campaign, first delete or close an existing one.',
  )
})

test("The 'Publish campaign' button is disabled when the open campaigns limit is reached", () => {
  render({orgOpenCampaignsCount: 10, maxOpenCampaigns: 10})

  const publishButton = screen.getByRole('button', {name: 'Publish campaign'})
  expect(publishButton).toBeDisabled()
})

test('It shows the validation error when the contact link is invalid', async () => {
  const {user} = render()

  const contactLinkInput = getContactLinkInput()
  await user.click(contactLinkInput)
  await user.paste('invalid link')

  expect(screen.getByText('Contact link must use http, https or mailto scheme')).toBeInTheDocument()
})

function getNameInput() {
  return screen.getByRole('textbox', {name: 'Campaign name *'})
}

function getDescriptionInput() {
  return screen.getByRole('textbox', {name: 'Short description *'})
}

function getContactLinkInput() {
  return screen.getByRole('textbox', {name: 'Contact link'})
}

function getDueDateButton() {
  return screen.getByLabelText(/date picker/i)
}

async function selectDueDate(user: User) {
  const datePickerButton = getDueDateButton()
  expect(datePickerButton).toBeInTheDocument()
  await user.click(datePickerButton)
  const datePicker = await screen.findByTestId('datepicker-panel')
  expect(datePicker).toBeInTheDocument()
  await user.click(datePicker)

  // Select the first day of the next month.
  // This avoids issues when the current date is the last day of the month
  // and therefore no date on the current page is valid.
  await user.click(within(datePicker).getByLabelText('Go to next month'))
  await user.click(within(datePicker).getByText('1'))
}

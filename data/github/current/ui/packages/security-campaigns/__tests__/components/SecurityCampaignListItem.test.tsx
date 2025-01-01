import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {SecurityCampaignListItem} from '../../components/SecurityCampaignListItem'
import type {SecurityCampaignWithCounts} from '@github-ui/security-campaigns-shared/SecurityCampaign'
import {getSecurityCampaignWithCounts} from '@github-ui/security-campaigns-shared/test-utils/mock-data'
import {IdProvider} from '@github-ui/list-view/ListViewIdContext'
import {VariantProvider} from '@github-ui/list-view/ListViewVariantContext'
import {TitleProvider} from '@github-ui/list-view/ListViewTitleContext'
import {mockFetch} from '@github-ui/mock-fetch'
import type {CloseSecurityCampaignResponse} from '../../hooks/use-close-security-campaign-mutation'

const closedAtOneDayAgo = new Date(Date.now() - 1000 * 60 * 60 * 24)

// Make the dates slightly under the threshold because we calculate daysLeft as a floor
const endsAtFiveDaysAgo = new Date(Date.now() - 1000 * 60 * 60 * 24 * 4.9)

const Wrapper = ({children}: {children?: React.ReactNode}) => (
  <IdProvider>
    <VariantProvider>
      <TitleProvider title="Closed campaigns">{children}</TitleProvider>
    </VariantProvider>
  </IdProvider>
)

const originalWindowLocation = window.location
const mockReload = jest.fn()

const navigateFn = jest.fn()
jest.mock('@github-ui/use-navigate', () => {
  return {
    useNavigate: () => navigateFn,
    useSearchParams: () => [new URLSearchParams(), jest.fn()],
  }
})

beforeAll(() => {
  Object.defineProperty(window, 'location', {configurable: true, value: {reload: mockReload}})
})

afterAll(() => {
  Object.defineProperty(window, 'location', {configurable: true, value: originalWindowLocation})
})

beforeEach(() => {
  jest.clearAllMocks()
})

test('Renders a non-overdue open campaign', async () => {
  const campaign: SecurityCampaignWithCounts = {
    ...getSecurityCampaignWithCounts(),
    name: 'Super campaign',
    number: 123,
    closedAt: null,
    openCount: 0,
    closedCount: 5,
  }

  render(
    <SecurityCampaignListItem
      organizationLogin="github"
      campaign={campaign}
      maxOpenCampaigns={10}
      openCampaignsCount={2}
      allowActions
      showLeadingIcon
      onMutationError={() => undefined}
    />,
    {
      wrapper: Wrapper,
    },
  )

  expect(screen.getByText('Super campaign')).toBeInTheDocument()
  expect(screen.queryByText(/Overdue/)).not.toBeInTheDocument()

  expect(screen.getByText('100% closed (5 alerts)')).toBeInTheDocument()
})

test('Renders a non-overdue closed campaign', async () => {
  const campaign: SecurityCampaignWithCounts = {
    ...getSecurityCampaignWithCounts(),
    name: 'Super campaign',
    number: 123,
    closedAt: closedAtOneDayAgo.toISOString(),
    openCount: 0,
    closedCount: 5,
  }

  render(
    <SecurityCampaignListItem
      organizationLogin="github"
      maxOpenCampaigns={10}
      openCampaignsCount={2}
      campaign={campaign}
      allowActions
      onMutationError={() => undefined}
    />,
    {
      wrapper: Wrapper,
    },
  )

  expect(screen.getByText('Super campaign')).toBeInTheDocument()
  expect(screen.queryByText(/Overdue/)).not.toBeInTheDocument()

  expect(screen.getByText('100% closed (5 alerts)')).toBeInTheDocument()
})

test('Renders an overdue open campaign', async () => {
  const campaign: SecurityCampaignWithCounts = {
    ...getSecurityCampaignWithCounts(),
    name: 'Super campaign',
    number: 123,
    closedAt: null,
    endsAt: endsAtFiveDaysAgo.toISOString(),
    openCount: 2,
    closedCount: 3,
  }

  render(
    <SecurityCampaignListItem
      organizationLogin="github"
      campaign={campaign}
      maxOpenCampaigns={10}
      openCampaignsCount={2}
      allowActions
      onMutationError={() => undefined}
    />,
    {
      wrapper: Wrapper,
    },
  )

  expect(screen.getByText('Super campaign')).toBeInTheDocument()

  expect(screen.getByText('60% closed (5 alerts)')).toBeInTheDocument()
})

test('Renders an overdue closed campaign', async () => {
  const campaign: SecurityCampaignWithCounts = {
    ...getSecurityCampaignWithCounts(),
    name: 'Super campaign',
    number: 123,
    closedAt: closedAtOneDayAgo.toISOString(),
    endsAt: endsAtFiveDaysAgo.toISOString(),
    openCount: 2,
    closedCount: 3,
  }

  render(
    <SecurityCampaignListItem
      organizationLogin="github"
      campaign={campaign}
      maxOpenCampaigns={10}
      openCampaignsCount={2}
      allowActions
      onMutationError={() => undefined}
    />,
    {
      wrapper: Wrapper,
    },
  )

  expect(screen.getByText('Super campaign')).toBeInTheDocument()

  expect(screen.getByText('60% closed (5 alerts)')).toBeInTheDocument()
})

test('Sends request to reopen a campaign', async () => {
  const campaign = {
    ...getSecurityCampaignWithCounts(),
    closedAt: closedAtOneDayAgo.toISOString(),
  }

  const mockReopenCampaignQuery = mockFetch.mockRoute(
    '/orgs/github/security/campaigns/5/reopen',
    {},
    {
      headers: new Headers({'Content-Type': 'application/json'}),
    },
  )

  const {user} = render(
    <SecurityCampaignListItem
      organizationLogin="github"
      campaign={campaign}
      maxOpenCampaigns={10}
      openCampaignsCount={2}
      allowActions
      onMutationError={() => undefined}
    />,
    {
      wrapper: Wrapper,
    },
  )

  await user.click(screen.getByRole('button', {name: 'More campaign options'}))

  await user.click(screen.getByRole('menuitem', {name: 'Re-open campaign'}))

  expect(mockReopenCampaignQuery).toHaveBeenCalled()
  expect(mockReload).toHaveBeenCalledTimes(1)
})

test('Reports error when reopening a campaign fails', async () => {
  const campaign = {
    ...getSecurityCampaignWithCounts(),
    closedAt: closedAtOneDayAgo.toISOString(),
  }

  const mockReopenCampaignQuery = mockFetch.mockRoute(
    '/orgs/github/security/campaigns/5/reopen',
    {message: 'This is a test error message'},
    {
      ok: false,
      status: 500,
      headers: new Headers({'Content-Type': 'application/json'}),
    },
  )

  const onMutationError = jest.fn()

  const {user} = render(
    <SecurityCampaignListItem
      organizationLogin="github"
      campaign={campaign}
      maxOpenCampaigns={10}
      openCampaignsCount={2}
      allowActions
      onMutationError={onMutationError}
    />,
    {
      wrapper: Wrapper,
    },
  )

  await user.click(screen.getByRole('button', {name: 'More campaign options'}))
  await user.click(screen.getByRole('menuitem', {name: 'Re-open campaign'}))

  expect(mockReopenCampaignQuery).toHaveBeenCalled()
  expect(mockReload).not.toHaveBeenCalled()
  expect(onMutationError).toHaveBeenCalledWith(
    'Unable to reopen campaign "User-controlled code injection": This is a test error message',
  )
})

test('Sends request to close a campaign', async () => {
  const campaign = getSecurityCampaignWithCounts()

  const mockCloseCampaignQuery = mockFetch.mockRoute(
    '/orgs/github/security/campaigns/5/close',
    {
      indexPageEnabled: false,
    } satisfies CloseSecurityCampaignResponse,
    {
      headers: new Headers({'Content-Type': 'application/json'}),
    },
  )

  const {user} = render(
    <SecurityCampaignListItem
      organizationLogin="github"
      campaign={campaign}
      maxOpenCampaigns={10}
      openCampaignsCount={2}
      allowActions
      onMutationError={() => undefined}
    />,
    {
      wrapper: Wrapper,
    },
  )

  await user.click(screen.getByRole('button', {name: 'More campaign options'}))

  await user.click(screen.getByRole('menuitem', {name: 'Close campaign'}))

  expect(mockCloseCampaignQuery).toHaveBeenCalled()
  expect(mockReload).toHaveBeenCalledTimes(1)
})

test('Sends request to close a campaign when index page is enabled', async () => {
  const campaign = getSecurityCampaignWithCounts()

  const mockCloseCampaignQuery = mockFetch.mockRoute(
    '/orgs/github/security/campaigns/5/close',
    {
      indexPageEnabled: true,
    } satisfies CloseSecurityCampaignResponse,
    {
      headers: new Headers({'Content-Type': 'application/json'}),
    },
  )

  const {user} = render(
    <SecurityCampaignListItem
      organizationLogin="github"
      campaign={campaign}
      maxOpenCampaigns={10}
      openCampaignsCount={2}
      allowActions
      onMutationError={() => undefined}
    />,
    {
      wrapper: Wrapper,
    },
  )

  await user.click(screen.getByRole('button', {name: 'More campaign options'}))

  await user.click(screen.getByRole('menuitem', {name: 'Close campaign'}))

  expect(mockCloseCampaignQuery).toHaveBeenCalled()
  expect(mockReload).toHaveBeenCalledTimes(1)
})

test('Reports error when closing a campaign fails', async () => {
  const campaign = getSecurityCampaignWithCounts()

  const mockCloseCampaignQuery = mockFetch.mockRoute(
    '/orgs/github/security/campaigns/5/close',
    {message: 'This is a test error message'},
    {
      ok: false,
      status: 500,
      headers: new Headers({'Content-Type': 'application/json'}),
    },
  )

  const onMutationError = jest.fn()

  const {user} = render(
    <SecurityCampaignListItem
      organizationLogin="github"
      campaign={campaign}
      maxOpenCampaigns={10}
      openCampaignsCount={2}
      allowActions
      onMutationError={onMutationError}
    />,
    {
      wrapper: Wrapper,
    },
  )

  await user.click(screen.getByRole('button', {name: 'More campaign options'}))
  await user.click(screen.getByRole('menuitem', {name: 'Close campaign'}))

  expect(mockCloseCampaignQuery).toHaveBeenCalled()
  expect(mockReload).not.toHaveBeenCalled()
  expect(onMutationError).toHaveBeenCalledWith(
    'Unable to close campaign "User-controlled code injection": This is a test error message',
  )
})

test('Sends request to delete a campaign', async () => {
  const campaign = getSecurityCampaignWithCounts()

  const mockDeleteCampaignQuery = mockFetch.mockRoute(
    '/orgs/github/security/campaigns/5',
    {},
    {headers: new Headers({'Content-Type': 'application/json'})},
  )

  const {user} = render(
    <SecurityCampaignListItem
      organizationLogin="github"
      campaign={campaign}
      maxOpenCampaigns={10}
      openCampaignsCount={2}
      allowActions
      onMutationError={() => undefined}
    />,
    {
      wrapper: Wrapper,
    },
  )

  await user.click(screen.getByRole('button', {name: 'More campaign options'}))
  await user.click(screen.getByRole('menuitem', {name: 'Delete campaign'}))
  await user.click(screen.getByRole('button', {name: 'Delete'}))

  expect(mockDeleteCampaignQuery).toHaveBeenCalled()
  expect(mockReload).toHaveBeenCalledTimes(1)
})

test('Reports error when deleting a campaign fails', async () => {
  const campaign = getSecurityCampaignWithCounts()

  const mockDeleteCampaignQuery = mockFetch.mockRoute(
    '/orgs/github/security/campaigns/5',
    {message: 'This is a test error message'},
    {
      ok: false,
      status: 500,
      headers: new Headers({'Content-Type': 'application/json'}),
    },
  )

  const onMutationError = jest.fn()

  const {user} = render(
    <SecurityCampaignListItem
      organizationLogin="github"
      campaign={campaign}
      maxOpenCampaigns={10}
      openCampaignsCount={2}
      allowActions
      onMutationError={onMutationError}
    />,
    {
      wrapper: Wrapper,
    },
  )

  await user.click(screen.getByRole('button', {name: 'More campaign options'}))
  await user.click(screen.getByRole('menuitem', {name: 'Delete campaign'}))
  await user.click(screen.getByRole('button', {name: 'Delete'}))

  expect(mockDeleteCampaignQuery).toHaveBeenCalled()
  expect(mockReload).not.toHaveBeenCalled()
  expect(onMutationError).toHaveBeenCalledWith(
    'Unable to delete campaign "User-controlled code injection": This is a test error message',
  )
})

test('Does not show the reopen option for a campaign that is not closed', async () => {
  const campaign = getSecurityCampaignWithCounts()

  const {user} = render(
    <SecurityCampaignListItem
      organizationLogin="github"
      campaign={campaign}
      maxOpenCampaigns={10}
      openCampaignsCount={2}
      allowActions
      onMutationError={() => undefined}
    />,
    {
      wrapper: Wrapper,
    },
  )

  await user.click(screen.getByRole('button', {name: 'More campaign options'}))

  expect(screen.queryByText('Re-open campaign')).not.toBeInTheDocument()
})

test('Does not show the close option for a campaign that is already closed', async () => {
  const campaign = {
    ...getSecurityCampaignWithCounts(),
    closedAt: closedAtOneDayAgo.toISOString(),
  }

  const {user} = render(
    <SecurityCampaignListItem
      organizationLogin="github"
      campaign={campaign}
      maxOpenCampaigns={10}
      openCampaignsCount={2}
      allowActions
      onMutationError={() => undefined}
    />,
    {
      wrapper: Wrapper,
    },
  )

  await user.click(screen.getByRole('button', {name: 'More campaign options'}))

  expect(screen.queryByText('Close campaign')).not.toBeInTheDocument()
})

test('Renders draft campaign without meta data', async () => {
  const campaign = {
    ...getSecurityCampaignWithCounts(),
    name: 'Draft campaign',
    publishedAt: null,
  }

  render(
    <SecurityCampaignListItem
      campaign={campaign}
      maxOpenCampaigns={10}
      openCampaignsCount={2}
      allowActions
      organizationLogin="github"
      onMutationError={() => undefined}
    />,
    {
      wrapper: Wrapper,
    },
  )

  expect(screen.getByText('Draft campaign')).toBeInTheDocument()
  expect(screen.getByText(/Created/)).toBeInTheDocument()
  expect(screen.queryByRole('progressbar')).not.toBeInTheDocument()
})

test('Shows publish and delete actions if campaign is draft', async () => {
  const campaign = {
    ...getSecurityCampaignWithCounts(),
    publishedAt: null,
    closedAt: null,
  }

  const {user} = render(
    <SecurityCampaignListItem
      organizationLogin="github"
      campaign={campaign}
      maxOpenCampaigns={10}
      openCampaignsCount={2}
      allowActions
      onMutationError={() => undefined}
    />,
    {
      wrapper: Wrapper,
    },
  )

  await user.click(screen.getByRole('button', {name: 'More campaign options'}))
  expect(screen.getByRole('menuitem', {name: 'Publish campaign'})).toBeInTheDocument()
  expect(screen.getByRole('menuitem', {name: 'Delete draft'})).toBeInTheDocument()
  expect(screen.queryByRole('menuitem', {name: 'Re-open campaign'})).not.toBeInTheDocument()
  expect(screen.queryByRole('menuitem', {name: 'Close campaign'})).not.toBeInTheDocument()
})

test('Redirects to publish page when clicking on publish campaign for a draft campaign', async () => {
  const campaign = {
    ...getSecurityCampaignWithCounts(),
    publishedAt: null,
    closedAt: null,
  }

  const {user} = render(
    <SecurityCampaignListItem
      organizationLogin="github"
      campaign={campaign}
      maxOpenCampaigns={10}
      openCampaignsCount={2}
      allowActions
      onMutationError={() => undefined}
    />,
    {
      wrapper: Wrapper,
    },
  )

  await user.click(screen.getByRole('button', {name: 'More campaign options'}))
  await user.click(screen.getByRole('menuitem', {name: 'Publish campaign'}))

  expect(navigateFn).toHaveBeenCalledWith(`/orgs/github/security/campaigns/${campaign.number}/publish`)
})

test('Sends request to delete a draft campaign', async () => {
  const campaign = getSecurityCampaignWithCounts({
    publishedAt: null,
    closedAt: null,
  })

  const mockDeleteCampaignQuery = mockFetch.mockRoute(
    `/orgs/github/security/campaigns/drafts/${campaign.number}`,
    {},
    {headers: new Headers({'Content-Type': 'application/json'})},
  )

  const {user} = render(
    <SecurityCampaignListItem
      organizationLogin="github"
      campaign={campaign}
      maxOpenCampaigns={10}
      openCampaignsCount={2}
      allowActions
      onMutationError={() => undefined}
    />,
    {
      wrapper: Wrapper,
    },
  )

  await user.click(screen.getByRole('button', {name: 'More campaign options'}))
  await user.click(screen.getByRole('menuitem', {name: 'Delete draft'}))
  await user.click(screen.getByRole('button', {name: 'Delete'}))

  expect(mockDeleteCampaignQuery).toHaveBeenCalled()
  expect(mockReload).toHaveBeenCalledTimes(1)
})

test('Reports error when deleting a draft campaign fails', async () => {
  const campaign = getSecurityCampaignWithCounts({
    publishedAt: null,
    closedAt: null,
  })

  const mockDeleteCampaignQuery = mockFetch.mockRoute(
    `/orgs/github/security/campaigns/drafts/${campaign.number}`,
    {message: 'This is a test error message'},
    {
      ok: false,
      status: 500,
      headers: new Headers({'Content-Type': 'application/json'}),
    },
  )

  const onMutationError = jest.fn()

  const {user} = render(
    <SecurityCampaignListItem
      organizationLogin="github"
      campaign={campaign}
      maxOpenCampaigns={10}
      openCampaignsCount={2}
      allowActions
      onMutationError={onMutationError}
    />,
    {
      wrapper: Wrapper,
    },
  )

  await user.click(screen.getByRole('button', {name: 'More campaign options'}))
  await user.click(screen.getByRole('menuitem', {name: 'Delete draft'}))
  await user.click(screen.getByRole('button', {name: 'Delete'}))

  expect(mockDeleteCampaignQuery).toHaveBeenCalled()
  expect(mockReload).not.toHaveBeenCalled()
  expect(onMutationError).toHaveBeenCalledWith(
    'Unable to delete draft campaign "User-controlled code injection": This is a test error message',
  )
})

import {screen} from '@testing-library/react'
import {render as reactRender} from '@github-ui/react-core/test-utils'
import {SecurityCampaignListItem, type SecurityCampaignListItemProps} from '../../components/SecurityCampaignListItem'
import {BannerProvider} from '@github-ui/role-assignments/banner-provider'
import {IdProvider} from '@github-ui/list-view/ListViewIdContext'
import {VariantProvider} from '@github-ui/list-view/ListViewVariantContext'
import {TitleProvider} from '@github-ui/list-view/ListViewTitleContext'
// eslint-disable-next-line no-restricted-imports
import {mockFetch} from '@github-ui/mock-fetch'
import type {CloseSecurityCampaignResponse} from '../../hooks/use-close-security-campaign-mutation'
import type {ReopenSecurityCampaignResponse} from '../../hooks/use-reopen-security-campaign-mutation'
import {getSecurityCampaignWithCounts} from '../../test-utils/mock-data'
import type {SecurityCampaignWithCounts} from '../../types/security-campaign'

const closedAtOneDayAgo = new Date(Date.now() - 1000 * 60 * 60 * 24)

// Make the dates slightly under the threshold because we calculate daysLeft as a floor
const endsAtFiveDaysAgo = new Date(Date.now() - 1000 * 60 * 60 * 24 * 4.9)

const Wrapper = ({children}: {children?: React.ReactNode}) => (
  <BannerProvider>
    <IdProvider>
      <VariantProvider>
        <TitleProvider title="Closed campaigns">{children}</TitleProvider>
      </VariantProvider>
    </IdProvider>
  </BannerProvider>
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

const defaultCampaign: SecurityCampaignWithCounts = {
  ...getSecurityCampaignWithCounts(),
  name: 'Super campaign',
  number: 5,
  closedAt: null,
  openCount: 0,
  closedCount: 5,
}

const onMutationError = jest.fn()

const defaultProps: SecurityCampaignListItemProps = {
  organizationLogin: 'github',
  campaign: defaultCampaign,
  maxOpenCampaigns: 10,
  openCampaignsCount: 2,
  hasOpenSpam: false,
  allowActions: true,
  showLeadingIcon: true,
  onMutationError,
}

const render = (props: Partial<SecurityCampaignListItemProps> = {}) =>
  reactRender(<SecurityCampaignListItem {...defaultProps} {...props} />, {
    wrapper: Wrapper,
  })

test('Renders a non-overdue open campaign', async () => {
  render()

  expect(screen.getByText('Super campaign')).toBeInTheDocument()
  expect(screen.queryByText(/Overdue/)).not.toBeInTheDocument()

  expect(screen.getByText('100% closed (5 alerts)')).toBeInTheDocument()
})

test('Renders a non-overdue closed campaign', async () => {
  const campaign: SecurityCampaignWithCounts = {
    ...defaultCampaign,
    closedAt: closedAtOneDayAgo.toISOString(),
  }

  render({campaign})

  expect(screen.getByText('Super campaign')).toBeInTheDocument()
  expect(screen.queryByText(/Overdue/)).not.toBeInTheDocument()

  expect(screen.getByText('100% closed (5 alerts)')).toBeInTheDocument()
})

test('Renders an overdue open campaign', async () => {
  const campaign: SecurityCampaignWithCounts = {
    ...defaultCampaign,
    endsAt: endsAtFiveDaysAgo.toISOString(),
    openCount: 2,
    closedCount: 3,
  }

  render({campaign})

  expect(screen.getByText('Super campaign')).toBeInTheDocument()

  expect(screen.getByText('60% closed (5 alerts)')).toBeInTheDocument()
})

test('Renders an overdue closed campaign', async () => {
  const campaign: SecurityCampaignWithCounts = {
    ...defaultCampaign,
    closedAt: closedAtOneDayAgo.toISOString(),
    endsAt: endsAtFiveDaysAgo.toISOString(),
    openCount: 2,
    closedCount: 3,
  }

  render({campaign})

  expect(screen.getByText('Super campaign')).toBeInTheDocument()

  expect(screen.getByText('60% closed (5 alerts)')).toBeInTheDocument()
})

test('Sends request to reopen a campaign', async () => {
  const campaign = {
    ...defaultCampaign,
    closedAt: closedAtOneDayAgo.toISOString(),
  }

  const mockReopenCampaignQuery = mockFetch.mockRoute(
    '/orgs/github/security/campaigns/5/reopen',
    {
      campaign: {
        ...defaultCampaign,
        closedAt: null,
      },
    } satisfies ReopenSecurityCampaignResponse,
    {
      headers: new Headers({'Content-Type': 'application/json'}),
    },
  )

  const {user} = render({campaign})

  await user.click(screen.getByRole('button', {name: `More ${campaign.name} campaign options`}))

  await user.click(screen.getByRole('menuitem', {name: 'Reopen campaign'}))

  expect(mockReopenCampaignQuery).toHaveBeenCalled()
  expect(mockReload).toHaveBeenCalledTimes(1)
})

test('Reports error when reopening a campaign fails', async () => {
  const campaign = {
    ...defaultCampaign,
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

  const {user} = render({campaign})

  await user.click(screen.getByRole('button', {name: `More ${campaign.name} campaign options`}))
  await user.click(screen.getByRole('menuitem', {name: 'Reopen campaign'}))

  expect(mockReopenCampaignQuery).toHaveBeenCalled()
  expect(mockReload).not.toHaveBeenCalled()
  expect(onMutationError).toHaveBeenCalledWith(
    'Unable to reopen campaign "Super campaign": This is a test error message',
  )
})

test('Sends request to close a campaign', async () => {
  const mockCloseCampaignQuery = mockFetch.mockRoute(
    '/orgs/github/security/campaigns/5/close',
    {
      campaign: {
        ...defaultCampaign,
        closedAt: new Date().toISOString(),
      },
      indexPageEnabled: false,
    } satisfies CloseSecurityCampaignResponse,
    {
      headers: new Headers({'Content-Type': 'application/json'}),
    },
  )

  const {user} = render()

  await user.click(screen.getByRole('button', {name: `More ${defaultCampaign.name} campaign options`}))

  await user.click(screen.getByRole('menuitem', {name: 'Close campaign'}))

  expect(mockCloseCampaignQuery).toHaveBeenCalled()
  expect(mockReload).toHaveBeenCalledTimes(1)
})

test('Sends request to close a campaign when index page is enabled', async () => {
  const mockCloseCampaignQuery = mockFetch.mockRoute(
    '/orgs/github/security/campaigns/5/close',
    {
      campaign: {
        ...defaultCampaign,
        closedAt: new Date().toISOString(),
      },
      indexPageEnabled: true,
    } satisfies CloseSecurityCampaignResponse,
    {
      headers: new Headers({'Content-Type': 'application/json'}),
    },
  )

  const {user} = render()

  await user.click(screen.getByRole('button', {name: `More ${defaultCampaign.name} campaign options`}))

  await user.click(screen.getByRole('menuitem', {name: 'Close campaign'}))

  expect(mockCloseCampaignQuery).toHaveBeenCalled()
  expect(mockReload).toHaveBeenCalledTimes(1)
})

test('Reports error when closing a campaign fails', async () => {
  const mockCloseCampaignQuery = mockFetch.mockRoute(
    '/orgs/github/security/campaigns/5/close',
    {message: 'This is a test error message'},
    {
      ok: false,
      status: 500,
      headers: new Headers({'Content-Type': 'application/json'}),
    },
  )

  const {user} = render()

  await user.click(screen.getByRole('button', {name: `More ${defaultCampaign.name} campaign options`}))
  await user.click(screen.getByRole('menuitem', {name: 'Close campaign'}))

  expect(mockCloseCampaignQuery).toHaveBeenCalled()
  expect(mockReload).not.toHaveBeenCalled()
  expect(onMutationError).toHaveBeenCalledWith(
    'Unable to close campaign "Super campaign": This is a test error message',
  )
})

test('Sends request to delete a campaign', async () => {
  const mockDeleteCampaignQuery = mockFetch.mockRoute(
    '/orgs/github/security/campaigns/5',
    {},
    {headers: new Headers({'Content-Type': 'application/json'})},
  )

  const {user} = render()

  await user.click(screen.getByRole('button', {name: `More ${defaultCampaign.name} campaign options`}))
  await user.click(screen.getByRole('menuitem', {name: 'Delete campaign'}))
  await user.click(screen.getByRole('button', {name: 'Delete'}))

  expect(mockDeleteCampaignQuery).toHaveBeenCalled()
  expect(mockReload).toHaveBeenCalledTimes(1)
})

test('Reports error when deleting a campaign fails', async () => {
  const mockDeleteCampaignQuery = mockFetch.mockRoute(
    '/orgs/github/security/campaigns/5',
    {message: 'This is a test error message'},
    {
      ok: false,
      status: 500,
      headers: new Headers({'Content-Type': 'application/json'}),
    },
  )

  const {user} = render()

  await user.click(screen.getByRole('button', {name: `More ${defaultCampaign.name} campaign options`}))
  await user.click(screen.getByRole('menuitem', {name: 'Delete campaign'}))
  await user.click(screen.getByRole('button', {name: 'Delete'}))

  expect(mockDeleteCampaignQuery).toHaveBeenCalled()
  expect(mockReload).not.toHaveBeenCalled()
  expect(onMutationError).toHaveBeenCalledWith(
    'Unable to delete campaign "Super campaign": This is a test error message',
  )
})

test('Does not show the reopen option for a campaign that is not closed', async () => {
  const {user} = render()

  await user.click(screen.getByRole('button', {name: `More ${defaultCampaign.name} campaign options`}))

  expect(screen.queryByText('Reopen campaign')).not.toBeInTheDocument()
})

test('Does not show the close option for a campaign that is already closed', async () => {
  const campaign = {
    ...defaultCampaign,
    closedAt: closedAtOneDayAgo.toISOString(),
  }

  const {user} = render({campaign})

  await user.click(screen.getByRole('button', {name: `More ${campaign.name} campaign options`}))

  expect(screen.queryByText('Close campaign')).not.toBeInTheDocument()
})

test('Renders draft campaign without meta data', async () => {
  const campaign = {
    ...defaultCampaign,
    name: 'Draft campaign',
    publishedAt: null,
  }

  render({campaign})

  expect(screen.getByText('Draft campaign')).toBeInTheDocument()
  expect(screen.getByText(/Created/)).toBeInTheDocument()
  expect(screen.queryByRole('progressbar')).not.toBeInTheDocument()
})

test('Shows publish and delete actions if campaign is draft', async () => {
  const campaign = {
    ...defaultCampaign,
    publishedAt: null,
    closedAt: null,
  }

  const {user} = render({campaign})

  await user.click(screen.getByRole('button', {name: `More ${campaign.name} campaign options`}))
  expect(screen.getByRole('menuitem', {name: 'Publish campaign'})).toBeInTheDocument()
  expect(screen.getByRole('menuitem', {name: 'Delete draft'})).toBeInTheDocument()
  expect(screen.queryByRole('menuitem', {name: 'Reopen campaign'})).not.toBeInTheDocument()
  expect(screen.queryByRole('menuitem', {name: 'Close campaign'})).not.toBeInTheDocument()
})

test('Shows publish action inactive message if campaign is draft', async () => {
  const campaign = {
    ...defaultCampaign,
    publishedAt: null,
    closedAt: null,
  }

  const {user} = render({campaign, hasOpenSpam: true, maxOpenCampaigns: 10, openCampaignsCount: 10})

  await user.click(screen.getByRole('button', {name: `More ${campaign.name} campaign options`}))
  const publishButton = screen.getByRole('menuitem', {name: 'Publish campaign'})
  expect(screen.getByRole('menuitem', {name: 'Publish campaign'})).toBeInTheDocument()
  expect(publishButton).toHaveAttribute('data-inactive', 'true')
  expect(publishButton).toHaveTextContent('Limit of 10 open and spam campaigns has been reached')
})

test('Redirects to publish page when clicking on publish campaign for a draft campaign', async () => {
  const campaign = {
    ...defaultCampaign,
    publishedAt: null,
    closedAt: null,
  }

  const {user} = render({campaign})

  await user.click(screen.getByRole('button', {name: `More ${campaign.name} campaign options`}))
  await user.click(screen.getByRole('menuitem', {name: 'Publish campaign'}))

  expect(navigateFn).toHaveBeenCalledWith(`/orgs/github/security/campaigns/${campaign.number}/publish`)
})

test('Sends request to delete a draft campaign', async () => {
  const campaign: SecurityCampaignWithCounts = {
    ...defaultCampaign,
    publishedAt: null,
    closedAt: null,
  }

  const mockDeleteCampaignQuery = mockFetch.mockRoute(
    `/orgs/github/security/campaigns/drafts/${campaign.number}`,
    {},
    {headers: new Headers({'Content-Type': 'application/json'})},
  )

  const {user} = render({campaign})

  await user.click(screen.getByRole('button', {name: `More ${campaign.name} campaign options`}))
  await user.click(screen.getByRole('menuitem', {name: 'Delete draft'}))
  await user.click(screen.getByRole('button', {name: 'Delete'}))

  expect(mockDeleteCampaignQuery).toHaveBeenCalled()
  expect(mockReload).toHaveBeenCalledTimes(1)
})

test('Reports error when deleting a draft campaign fails', async () => {
  const campaign: SecurityCampaignWithCounts = {
    ...defaultCampaign,
    publishedAt: null,
    closedAt: null,
  }

  const mockDeleteCampaignQuery = mockFetch.mockRoute(
    `/orgs/github/security/campaigns/drafts/${campaign.number}`,
    {message: 'This is a test error message'},
    {
      ok: false,
      status: 500,
      headers: new Headers({'Content-Type': 'application/json'}),
    },
  )

  const {user} = render({campaign})

  await user.click(screen.getByRole('button', {name: `More ${campaign.name} campaign options`}))
  await user.click(screen.getByRole('menuitem', {name: 'Delete draft'}))
  await user.click(screen.getByRole('button', {name: 'Delete'}))

  expect(mockDeleteCampaignQuery).toHaveBeenCalled()
  expect(mockReload).not.toHaveBeenCalled()
  expect(onMutationError).toHaveBeenCalledWith(
    'Unable to delete draft campaign "Super campaign": This is a test error message',
  )
})

import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {ClosedSecurityCampaignListItem} from '../../components/ClosedSecurityCampaignListItem'
import {QueryClientProvider} from '@tanstack/react-query'
import {getQueryClient} from '@github-ui/security-campaigns-shared/utils/query-client'
import type {SecurityCampaignWithCounts} from '@github-ui/security-campaigns-shared/SecurityCampaign'
import {getSecurityCampaignWithCounts} from '@github-ui/security-campaigns-shared/test-utils/mock-data'
import {IdProvider} from '@github-ui/list-view/ListViewIdContext'
import {VariantProvider} from '@github-ui/list-view/ListViewVariantContext'
import {TitleProvider} from '@github-ui/list-view/ListViewTitleContext'
import {mockFetch} from '@github-ui/mock-fetch'

const closedAtOneDayAgo = new Date(Date.now() - 1000 * 60 * 60 * 24)

// Make the dates slightly under the threshold because we calculate daysLeft as a floor
const endsAtFiveDaysAgo = new Date(Date.now() - 1000 * 60 * 60 * 24 * 4.9)

const Wrapper = ({children}: {children?: React.ReactNode}) => (
  <IdProvider>
    <VariantProvider>
      <TitleProvider title="Closed campaigns">
        <QueryClientProvider client={getQueryClient()}>{children}</QueryClientProvider>
      </TitleProvider>
    </VariantProvider>
  </IdProvider>
)

const originalWindowLocation = window.location
const mockSetHref = jest.fn()
const mockReload = jest.fn()

beforeAll(() => {
  Object.defineProperty(window, 'location', {configurable: true, value: {reload: mockReload}})
  Object.defineProperty(window.location, 'href', {set: mockSetHref})
})

afterAll(() => {
  Object.defineProperty(window, 'location', {configurable: true, value: originalWindowLocation})
})

beforeEach(() => {
  jest.clearAllMocks()
})

test('Renders a non-overdue campaign', async () => {
  const campaign: SecurityCampaignWithCounts = {
    ...getSecurityCampaignWithCounts(),
    name: 'Super campaign',
    number: 123,
    closedAt: closedAtOneDayAgo.toISOString(),
    openCount: 0,
    closedCount: 5,
  }

  render(<ClosedSecurityCampaignListItem campaign={campaign} onMutationError={() => undefined} />, {
    wrapper: Wrapper,
  })

  expect(screen.getByText('Super campaign')).toBeInTheDocument()
  expect(screen.queryByText(/Overdue/)).not.toBeInTheDocument()

  expect(screen.getByText('100% closed (5 alerts)')).toBeInTheDocument()
})

test('Renders an overdue campaign', async () => {
  const campaign: SecurityCampaignWithCounts = {
    ...getSecurityCampaignWithCounts(),
    name: 'Super campaign',
    number: 123,
    closedAt: closedAtOneDayAgo.toISOString(),
    endsAt: endsAtFiveDaysAgo.toISOString(),
    openCount: 2,
    closedCount: 3,
  }

  render(<ClosedSecurityCampaignListItem campaign={campaign} onMutationError={() => undefined} />, {
    wrapper: Wrapper,
  })

  expect(screen.getByText('Super campaign')).toBeInTheDocument()

  expect(screen.getByText('60% closed (5 alerts)')).toBeInTheDocument()
})

test('Sends request to reopen a campaign', async () => {
  const campaign = getSecurityCampaignWithCounts()

  const reopenCampaignResponse = {redirect: campaign.showPath}
  const mockReopenCampaignQuery = mockFetch.mockRoute(campaign.reopenPath, reopenCampaignResponse, {
    headers: new Headers({'Content-Type': 'application/json'}),
  })

  const {user} = render(<ClosedSecurityCampaignListItem campaign={campaign} onMutationError={() => undefined} />, {
    wrapper: Wrapper,
  })

  await user.click(screen.getByRole('button', {name: 'More campaign options'}))

  await user.click(screen.getByRole('menuitem', {name: 'Re-open campaign'}))

  expect(mockReopenCampaignQuery).toHaveBeenCalled()
  expect(mockSetHref).toHaveBeenCalledWith(reopenCampaignResponse.redirect)
  expect(mockSetHref).toHaveBeenCalledTimes(1)
})

test('Reports error when reopening a campaign fails', async () => {
  const campaign = getSecurityCampaignWithCounts()

  const mockReopenCampaignQuery = mockFetch.mockRoute(
    campaign.reopenPath,
    {message: 'This is a test error message'},
    {
      ok: false,
      status: 500,
      headers: new Headers({'Content-Type': 'application/json'}),
    },
  )

  const onMutationError = jest.fn()

  const {user} = render(<ClosedSecurityCampaignListItem campaign={campaign} onMutationError={onMutationError} />, {
    wrapper: Wrapper,
  })

  await user.click(screen.getByRole('button', {name: 'More campaign options'}))
  await user.click(screen.getByRole('menuitem', {name: 'Re-open campaign'}))

  expect(mockReopenCampaignQuery).toHaveBeenCalled()
  expect(mockSetHref).not.toHaveBeenCalled()
  expect(onMutationError).toHaveBeenCalledWith(
    'Unable to reopen campaign "User-controlled code injection": This is a test error message',
  )
})

test('Sends request to delete a campaign', async () => {
  const campaign = getSecurityCampaignWithCounts()

  const mockDeleteCampaignQuery = mockFetch.mockRoute(
    campaign.deletePath,
    {},
    {headers: new Headers({'Content-Type': 'application/json'})},
  )

  const {user} = render(<ClosedSecurityCampaignListItem campaign={campaign} onMutationError={() => undefined} />, {
    wrapper: Wrapper,
  })

  await user.click(screen.getByRole('button', {name: 'More campaign options'}))
  await user.click(screen.getByRole('menuitem', {name: 'Delete campaign'}))
  await user.click(screen.getByRole('button', {name: 'Delete'}))

  expect(mockDeleteCampaignQuery).toHaveBeenCalled()
  expect(mockReload).toHaveBeenCalledTimes(1)
})

test('Reports error when deleting a campaign fails', async () => {
  const campaign = getSecurityCampaignWithCounts()

  const mockDeleteCampaignQuery = mockFetch.mockRoute(
    campaign.deletePath,
    {message: 'This is a test error message'},
    {
      ok: false,
      status: 500,
      headers: new Headers({'Content-Type': 'application/json'}),
    },
  )

  const onMutationError = jest.fn()

  const {user} = render(<ClosedSecurityCampaignListItem campaign={campaign} onMutationError={onMutationError} />, {
    wrapper: Wrapper,
  })

  await user.click(screen.getByRole('button', {name: 'More campaign options'}))
  await user.click(screen.getByRole('menuitem', {name: 'Delete campaign'}))
  await user.click(screen.getByRole('button', {name: 'Delete'}))

  expect(mockDeleteCampaignQuery).toHaveBeenCalled()
  expect(mockReload).not.toHaveBeenCalled()
  expect(onMutationError).toHaveBeenCalledWith(
    'Unable to delete campaign "User-controlled code injection": This is a test error message',
  )
})

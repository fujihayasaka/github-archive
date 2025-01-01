import {render} from '@github-ui/react-core/test-utils'
import type {GetClosedCampaignsResponse} from '../../types/get-closed-campaigns-response'
import {getSecurityCampaignWithCounts} from '@github-ui/security-campaigns-shared/test-utils/mock-data'
import {mockFetch} from '@github-ui/mock-fetch'
import {screen, waitFor} from '@testing-library/react'
import {ClosedSecurityCampaignsList} from '../../components/ClosedSecurityCampaignsList'
import {QueryClientProvider} from '@tanstack/react-query'
import {getQueryClient} from '@github-ui/security-campaigns-shared/utils/query-client'

const closedCampaignsPath = '/orgs/github/security/campaigns/closed/list'

const Wrapper = ({children}: {children?: React.ReactNode}) => (
  <QueryClientProvider client={getQueryClient()}>{children}</QueryClientProvider>
)

test('Requests and renders a single page of closed campaigns', async () => {
  const getClosedCampaignsResponse: GetClosedCampaignsResponse = {
    campaigns: [
      {
        ...getSecurityCampaignWithCounts(),
        id: 1,
        name: 'The best campaign',
        number: 123,
      },
      {
        ...getSecurityCampaignWithCounts(),
        id: 2,
        name: 'Another campaign',
        number: 456,
      },
    ],
  }
  const mockGetClosedCampaignsQuery = mockFetch.mockRoute(`${closedCampaignsPath}?`, getClosedCampaignsResponse, {
    headers: new Headers({'Content-Type': 'application/json'}),
  })

  render(<ClosedSecurityCampaignsList closedCampaignsCounts={15} closedCampaignsPath={closedCampaignsPath} />, {
    wrapper: Wrapper,
  })

  await waitFor(() => {
    expect(screen.getByText('The best campaign')).toBeInTheDocument()
  })
  await waitFor(() => {
    expect(screen.getByText('Another campaign')).toBeInTheDocument()
  })

  expect(screen.queryByRole('button', {name: 'Previous'})).toBeDisabled()
  expect(screen.queryByRole('button', {name: 'Next'})).toBeDisabled()

  expect(mockGetClosedCampaignsQuery).toHaveBeenCalledTimes(1)
})

test('Requests the next page of closed campaigns', async () => {
  const firstGetClosedCampaignsResponse: GetClosedCampaignsResponse = {
    campaigns: [
      {
        ...getSecurityCampaignWithCounts(),
        id: 1,
        name: 'The best campaign',
        number: 123,
      },
    ],
    nextCursor: '123',
  }
  const firstMockGetClosedCampaignsQuery = mockFetch.mockRoute(
    `${closedCampaignsPath}?`,
    firstGetClosedCampaignsResponse,
    {headers: new Headers({'Content-Type': 'application/json'})},
  )

  const {user} = render(
    <ClosedSecurityCampaignsList closedCampaignsCounts={15} closedCampaignsPath={closedCampaignsPath} />,
    {wrapper: Wrapper},
  )

  await waitFor(() => {
    expect(screen.getByText('The best campaign')).toBeInTheDocument()
  })
  await waitFor(() => {
    expect(screen.queryByText('Another campaign')).not.toBeInTheDocument()
  })

  expect(screen.queryByRole('button', {name: 'Previous'})).toBeDisabled()
  expect(screen.queryByRole('button', {name: 'Next'})).not.toBeDisabled()

  expect(firstMockGetClosedCampaignsQuery).toHaveBeenCalledTimes(1)

  const secondGetClosedCampaignsResponse: GetClosedCampaignsResponse = {
    campaigns: [
      {
        ...getSecurityCampaignWithCounts(),
        id: 2,
        name: 'Another campaign',
        number: 456,
      },
    ],
    prevCursor: '456',
  }
  const secondMockGetClosedCampaignsQuery = mockFetch.mockRoute(
    `${closedCampaignsPath}?after=123`,
    secondGetClosedCampaignsResponse,
    {headers: new Headers({'Content-Type': 'application/json'})},
  )

  await user.click(screen.getByRole('button', {name: 'Next'}))

  await waitFor(() => {
    expect(screen.getByText('Another campaign')).toBeInTheDocument()
  })
  expect(screen.queryByText('The best campaign')).not.toBeInTheDocument()

  expect(screen.queryByRole('button', {name: 'Previous'})).not.toBeDisabled()
  expect(screen.queryByRole('button', {name: 'Next'})).toBeDisabled()

  expect(secondMockGetClosedCampaignsQuery).toHaveBeenCalledTimes(1)
})

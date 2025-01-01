import {render} from '@github-ui/react-core/test-utils'
import type {GetCampaignsResponse} from '../../types/get-campaigns-response'
import {getSecurityCampaignWithCounts} from '@github-ui/security-campaigns-shared/test-utils/mock-data'
import {mockFetch} from '@github-ui/mock-fetch'
import {screen, waitFor} from '@testing-library/react'
import {SecurityCampaignsList} from '../../components/SecurityCampaignsList'

const organizationLogin = 'github'
const openCampaignsPath = `/orgs/${organizationLogin}/security/campaigns/open/list`
const closedCampaignsPath = `/orgs/${organizationLogin}/security/campaigns/closed/list`
const draftCampaignsPath = `/orgs/${organizationLogin}/security/campaigns/drafts`

test('Requests and renders a single page of campaigns', async () => {
  const getCampaignsResponse: GetCampaignsResponse = {
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
  const mockGetOpenCampaignsQuery = mockFetch.mockRoute(`${openCampaignsPath}?`, getCampaignsResponse, {
    headers: new Headers({'Content-Type': 'application/json'}),
  })

  render(
    <SecurityCampaignsList
      openCount={3}
      closedCount={15}
      draftCount={10}
      showFullView
      organizationLogin={organizationLogin}
      maxOpenCampaigns={10}
      draftCampaignsEnabled={false}
    />,
  )

  await waitFor(() => {
    expect(screen.getByText('The best campaign')).toBeInTheDocument()
  })
  await waitFor(() => {
    expect(screen.getByText('Another campaign')).toBeInTheDocument()
  })

  expect(screen.queryByRole('button', {name: 'Previous'})).not.toBeInTheDocument()
  expect(screen.queryByRole('button', {name: 'Next'})).not.toBeInTheDocument()

  expect(mockGetOpenCampaignsQuery).toHaveBeenCalledTimes(1)
})

test('Requests the next page of closed campaigns', async () => {
  const openGetCampaignsResponse: GetCampaignsResponse = {
    campaigns: [],
  }
  const firstMockGetCampaignsQuery = mockFetch.mockRoute(`${openCampaignsPath}?`, openGetCampaignsResponse, {
    headers: new Headers({'Content-Type': 'application/json'}),
  })

  const {user} = render(
    <SecurityCampaignsList
      openCount={3}
      closedCount={15}
      draftCount={10}
      showFullView
      organizationLogin={organizationLogin}
      maxOpenCampaigns={10}
      draftCampaignsEnabled={false}
    />,
  )
  expect(firstMockGetCampaignsQuery).toHaveBeenCalledTimes(1)

  const firstGetClosedCampaignsResponse: GetCampaignsResponse = {
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
    {
      headers: new Headers({'Content-Type': 'application/json'}),
    },
  )

  await user.click(screen.getByRole('link', {name: 'Closed (15)'}))

  await waitFor(() => {
    expect(screen.getByText('The best campaign')).toBeInTheDocument()
  })
  expect(screen.queryByText('Another campaign')).not.toBeInTheDocument()

  expect(screen.queryByRole('button', {name: 'Previous'})).toBeDisabled()
  expect(screen.queryByRole('button', {name: 'Next'})).not.toBeDisabled()

  expect(firstMockGetClosedCampaignsQuery).toHaveBeenCalledTimes(1)

  const secondGetClosedCampaignsResponse: GetCampaignsResponse = {
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
  const secondMockGetCampaignsQuery = mockFetch.mockRoute(
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

  expect(secondMockGetCampaignsQuery).toHaveBeenCalledTimes(1)
})

it('Sends closed request when clicking the close button', async () => {
  const getCampaignsResponse: GetCampaignsResponse = {
    campaigns: [],
  }
  const mockGetOpenCampaignsQuery = mockFetch.mockRoute(`${openCampaignsPath}?`, getCampaignsResponse, {
    headers: new Headers({'Content-Type': 'application/json'}),
  })

  const mockGetClosedCampaignsQuery = mockFetch.mockRoute(`${closedCampaignsPath}?`, getCampaignsResponse, {
    headers: new Headers({'Content-Type': 'application/json'}),
  })

  const {user} = render(
    <SecurityCampaignsList
      openCount={3}
      closedCount={15}
      draftCount={10}
      showFullView
      organizationLogin={organizationLogin}
      maxOpenCampaigns={10}
      draftCampaignsEnabled={false}
    />,
  )

  await user.click(
    screen.getByRole('link', {
      name: /^Closed/,
    }),
  )

  expect(mockGetOpenCampaignsQuery).toHaveBeenCalledTimes(1)
  expect(mockGetClosedCampaignsQuery).toHaveBeenCalledTimes(1)
})

it('Sends open request when clicking the open button', async () => {
  const getCampaignsResponse: GetCampaignsResponse = {
    campaigns: [],
  }
  const mockGetOpenCampaignsQuery = mockFetch.mockRoute(`${openCampaignsPath}?`, getCampaignsResponse, {
    headers: new Headers({'Content-Type': 'application/json'}),
  })

  const mockGetClosedCampaignsQuery = mockFetch.mockRoute(`${closedCampaignsPath}?`, getCampaignsResponse, {
    headers: new Headers({'Content-Type': 'application/json'}),
  })

  const {user} = render(
    <SecurityCampaignsList
      openCount={3}
      closedCount={15}
      draftCount={10}
      showFullView
      organizationLogin={organizationLogin}
      maxOpenCampaigns={10}
      draftCampaignsEnabled={false}
    />,
  )

  await user.click(
    screen.getByRole('link', {
      name: /^Closed/,
    }),
  )

  await user.click(
    screen.getByRole('link', {
      name: /^Open/,
    }),
  )

  expect(mockGetOpenCampaignsQuery).toHaveBeenCalledTimes(2)
  expect(mockGetClosedCampaignsQuery).toHaveBeenCalledTimes(1)
})

test('Requests and renders a single page of campaigns without fullview', async () => {
  const getCampaignsResponse: GetCampaignsResponse = {
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
  const mockGetOpenCampaignsQuery = mockFetch.mockRoute(`${openCampaignsPath}?`, getCampaignsResponse, {
    headers: new Headers({'Content-Type': 'application/json'}),
  })

  render(
    <SecurityCampaignsList
      openCount={3}
      closedCount={15}
      draftCount={10}
      showFullView={false}
      organizationLogin={organizationLogin}
      maxOpenCampaigns={10}
      draftCampaignsEnabled={false}
    />,
  )

  await waitFor(() => {
    expect(screen.getByText('The best campaign')).toBeInTheDocument()
  })

  expect(screen.getByText('Another campaign')).toBeInTheDocument()
  expect(screen.queryByRole('link', {name: /^Open/})).not.toBeInTheDocument()
  expect(screen.queryByRole('link', {name: /^Closed/})).not.toBeInTheDocument()

  expect(mockGetOpenCampaignsQuery).toHaveBeenCalledTimes(1)
})

test('Requests and renders draft campaigns', async () => {
  const getCampaignsResponse: GetCampaignsResponse = {
    campaigns: [
      {
        ...getSecurityCampaignWithCounts(),
        id: 1,
        name: 'The best campaign',
        number: 123,
        publishedAt: null,
      },
      {
        ...getSecurityCampaignWithCounts(),
        id: 2,
        name: 'Another campaign',
        number: 456,
        publishedAt: null,
      },
    ],
  }
  const mockGetDraftCampaignsQuery = mockFetch.mockRoute(`${draftCampaignsPath}?`, getCampaignsResponse, {
    headers: new Headers({'Content-Type': 'application/json'}),
  })

  const {user} = render(
    <SecurityCampaignsList
      openCount={3}
      closedCount={15}
      draftCount={10}
      showFullView
      organizationLogin={organizationLogin}
      maxOpenCampaigns={10}
      draftCampaignsEnabled
    />,
  )

  await user.click(
    screen.getByRole('link', {
      name: /^Draft/,
    }),
  )
  await waitFor(() => {
    expect(screen.getByText('The best campaign')).toBeInTheDocument()
  })

  expect(screen.getByText('Another campaign')).toBeInTheDocument()

  expect(mockGetDraftCampaignsQuery).toHaveBeenCalledTimes(1)
})

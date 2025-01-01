import {screen, waitFor} from '@testing-library/react'
import {RepoProgressMetric, type RepoProgressMetricProps} from '../../components/RepoProgressMetric'
import {render as reactRender} from '@github-ui/react-core/test-utils'
import type {GetAlertsResponse} from '../../types/get-alerts-response'
import {mockFetch} from '@github-ui/mock-fetch'
import {defaultQuery} from '../../components/AlertsList'
import {QueryClientProvider} from '@tanstack/react-query'
import {getQueryClient} from '@github-ui/security-campaigns-shared/utils/query-client'

const alertsPath = '/github/security-campaigns/security/campaigns/1/alerts'
const orgCampaignPath = '/orgs/github/security/campaigns/1'

const defaultProps: RepoProgressMetricProps = {
  alertsPath,
  endsAt: new Date('2023-01-20T00:00:00Z'),
  createdAt: new Date('2023-01-01T00:00:00Z'),
  orgCampaignPath,
}

const defaultGetAlertsResponse: GetAlertsResponse = {
  alerts: [],
  openCount: 3,
  closedCount: 2,
  openWithLinksCount: 0,
  nextCursor: '',
  prevCursor: '',
}

const fakedSystemDate = new Date('2023-01-10T00:00:00Z')

async function render(props?: Partial<RepoProgressMetricProps>) {
  reactRender(
    <QueryClientProvider client={getQueryClient()}>
      <RepoProgressMetric {...defaultProps} {...props} />
    </QueryClientProvider>,
  )

  await waitFor(() => {
    expect(screen.getByRole('progressbar')).toBeInTheDocument()
  })
}

beforeEach(() => {
  jest.useFakeTimers().setSystemTime(fakedSystemDate)

  mockFetch.mockRoute(`${alertsPath}?query=${encodeURIComponent(defaultQuery)}`, defaultGetAlertsResponse, {
    headers: new Headers({
      'Content-Type': 'application/json',
    }),
  })
})

test('Requests and renders alert counts', async () => {
  await render()

  await screen.findByRole('progressbar', {value: {now: 40}})
  expect(screen.getByText('40% (2 alerts)')).toBeInTheDocument()
  expect(screen.getByText('3 alerts left')).toBeInTheDocument()
})

test('Renders a link to the organization-level campaign if orgCampaignPath is provided', async () => {
  await render()

  expect(screen.getByText('View organization-level campaign')).toBeInTheDocument()
})

test('Does not render a link to the organization-level campaign if orgCampaignPath is not provided', async () => {
  await render({
    orgCampaignPath: null,
  })

  expect(screen.queryByText('View organization-level campaign')).not.toBeInTheDocument()
})

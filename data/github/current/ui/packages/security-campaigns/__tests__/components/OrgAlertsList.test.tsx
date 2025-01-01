import {screen, waitFor, within} from '@testing-library/react'
import {render as reactRender} from '@github-ui/react-core/test-utils'
import {mockFetch} from '@github-ui/mock-fetch'
import {createSecurityCampaignAlert} from '../../test-utils/mock-data'
import type {GetAlertsResponse} from '../../types/get-alerts-response'
import {OrgAlertsList, type OrgAlertsListProps} from '../../components/OrgAlertsList'
import {defaultQuery} from '../../hooks/use-alerts-params'

jest.setTimeout(10_000)

const openAlerts = [
  createSecurityCampaignAlert({
    number: 123,
    isFixed: false,
    isDismissed: false,
  }),
  createSecurityCampaignAlert({
    number: 125,
    isFixed: false,
    isDismissed: false,
  }),
  createSecurityCampaignAlert({
    number: 142,
    isFixed: false,
    isDismissed: false,
  }),
]
const closedAlerts = [
  createSecurityCampaignAlert({
    number: 67,
    isFixed: true,
    isDismissed: false,
  }),
  createSecurityCampaignAlert({
    number: 893,
    isFixed: true,
    isDismissed: false,
  }),
]
const openAlertsPageTwo = [
  createSecurityCampaignAlert({
    number: 235,
    isFixed: false,
    isDismissed: false,
  }),
]

const defaultGetAlertsResponse: GetAlertsResponse = {
  alerts: openAlerts,
  openCount: openAlerts.length + openAlertsPageTwo.length,
  closedCount: closedAlerts.length,
  openWithLinksCount: 0,
  nextCursor: 'cursornext',
  prevCursor: '',
}

const alertsPath = '/github/security-campaigns/security/campaigns/1/alerts'

const defaultProps: OrgAlertsListProps = {
  alertsPath,
  query: defaultQuery,
  cursor: null,
  onStateFilterChange: jest.fn(),
  setCursor: jest.fn(),
  alertParentLink: {kind: 'campaign', campaignNumber: 1},
}
const render = async (props: Partial<OrgAlertsListProps> = {}) => {
  const view = reactRender(<OrgAlertsList {...defaultProps} {...props} />)

  // Wait for the alerts to load
  await waitFor(() => {
    expect(
      screen.getByRole('list', {
        name: `${defaultGetAlertsResponse.openCount + defaultGetAlertsResponse.closedCount} alerts`,
      }),
    ).toBeInTheDocument()
  })

  return view
}

beforeEach(() => {
  mockFetch.mockRoute(`${alertsPath}?query=${encodeURIComponent(defaultQuery)}`, defaultGetAlertsResponse, {
    headers: new Headers({
      'Content-Type': 'application/json',
    }),
  })
})

it('renders', async () => {
  await render()
  const list = screen.getByRole('list', {
    name: '6 alerts',
  })
  expect(within(list).getAllByRole('listitem')).toHaveLength(3)
  expect(within(list).getAllByRole('link')).toHaveLength(6)
})

it('sends closed request when clicking the close button', async () => {
  const onStateFilterChange = jest.fn()
  const {user} = await render({onStateFilterChange})

  await user.click(
    screen.getByRole('link', {
      name: /^Closed/,
    }),
  )

  expect(onStateFilterChange).toHaveBeenCalledWith('closed')
})

it('uses the query', async () => {
  const mock = mockFetch.mockRoute(
    `${alertsPath}?query=${encodeURIComponent('is:closed')}`,
    {
      ...defaultGetAlertsResponse,
      alerts: closedAlerts,
    } satisfies GetAlertsResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  await render({query: 'is:closed'})

  const list = screen.getByRole('list', {
    name: '6 alerts',
  })
  expect(within(list).getAllByRole('listitem')).toHaveLength(2)

  expect(mock).toHaveBeenCalled()
})

it('can paginate', async () => {
  const setCursor = jest.fn()
  const {user, rerender} = await render({setCursor})

  expect(
    screen.getByRole('button', {
      name: 'Previous',
    }),
  ).toBeDisabled()

  const list = screen.getByRole('list', {
    name: '6 alerts',
  })

  const nextPageMock = mockFetch.mockRoute(
    `${alertsPath}?query=${encodeURIComponent(defaultQuery)}&after=cursornext`,
    {
      ...defaultGetAlertsResponse,
      alerts: openAlertsPageTwo,
      nextCursor: '',
      prevCursor: 'cursorprev',
    } satisfies GetAlertsResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  await user.click(
    screen.getByRole('button', {
      name: 'Next',
    }),
  )

  expect(setCursor).toHaveBeenNthCalledWith(1, {after: 'cursornext'})
  rerender(<OrgAlertsList {...defaultProps} cursor={{after: 'cursornext'}} setCursor={setCursor} />)

  await waitFor(() => {
    expect(within(list).getAllByRole('listitem')).toHaveLength(1)
  })
  expect(
    screen.getByRole('button', {
      name: 'Next',
    }),
  ).toBeDisabled()

  expect(nextPageMock).toHaveBeenCalled()

  const prevPageMock = mockFetch.mockRoute(
    `${alertsPath}?query=${encodeURIComponent(defaultQuery)}&before=cursorprev`,
    {
      ...defaultGetAlertsResponse,
      nextCursor: 'cursornext',
      prevCursor: '',
    } satisfies GetAlertsResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  await user.click(
    screen.getByRole('button', {
      name: 'Previous',
    }),
  )

  expect(setCursor).toHaveBeenNthCalledWith(2, {before: 'cursorprev'})
  rerender(<OrgAlertsList {...defaultProps} cursor={{before: 'cursorprev'}} setCursor={setCursor} />)

  await waitFor(() => {
    expect(within(list).getAllByRole('listitem')).toHaveLength(3)
  })
  expect(prevPageMock).toHaveBeenCalled()
}, 20_000)

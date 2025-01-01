import {screen, waitFor, within} from '@testing-library/react'
import {render as reactRender} from '@github-ui/react-core/test-utils'
import {mockFetch} from '@github-ui/mock-fetch'
import {createSecurityCampaignAlert, createSecurityCampaignAlertGroup} from '../../test-utils/mock-data'
import type {GetAlertsResponse} from '../../types/get-alerts-response'
import {defaultQuery} from '../../components/AlertsList'
import type {GetAlertsGroupsResponse} from '../../types/get-alerts-groups-response'
import {OrgAlertsGroups, type OrgAlertsGroupsProps} from '../../components/OrgAlertsGroups'
import {TestWrapper} from '@github-ui/security-campaigns-shared/test-utils/TestWrapper'
import type {AlertListItemProps} from '../../components/AlertListItem'

jest.setTimeout(4_500)

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

const openAlertsGroups = [
  createSecurityCampaignAlertGroup({
    title: 'github/security-campaigns-1',
    openCount: openAlerts.length + openAlertsPageTwo.length,
    closedCount: closedAlerts.length,
    repositories: ['security-campaigns/test-1'],
  }),
  createSecurityCampaignAlertGroup({
    title: 'github/security-campaigns-2',
    openCount: openAlerts.length + openAlertsPageTwo.length,
    closedCount: closedAlerts.length,
    repositories: ['security-campaigns/test-2'],
  }),
  createSecurityCampaignAlertGroup({
    title: 'github/security-campaigns-3',
    openCount: openAlerts.length + openAlertsPageTwo.length,
    closedCount: closedAlerts.length,
    repositories: ['security-campaigns/test-3'],
  }),
]

const openAlertsGroupsPageTwo = [
  createSecurityCampaignAlertGroup({
    openCount: openAlerts.length + openAlertsPageTwo.length,
    closedCount: closedAlerts.length,
  }),
]

const defaultGetAlertsGroupsResponse: GetAlertsGroupsResponse = {
  groups: openAlertsGroups,
  openCount: openAlerts.length + openAlertsPageTwo.length,
  closedCount: closedAlerts.length,
  nextCursor: 'cursornext',
  prevCursor: '',
}

const singleGetAlertsGroupsResponse: GetAlertsGroupsResponse = {
  groups: openAlertsGroups.slice(0, 1),
  openCount: openAlerts.length,
  closedCount: closedAlerts.length,
  nextCursor: '',
  prevCursor: '',
}

const alertsPath = '/github/security-campaigns/security/campaigns/1/alerts'
const alertsGroupsPath = '/github/security-campaigns/security/campaigns/1/alerts-groups'

const mockDefaultAlertsGroupsRequest = () => {
  return mockFetch.mockRoute(
    `${alertsGroupsPath}?query=${encodeURIComponent(defaultQuery)}&group=repository`,
    defaultGetAlertsGroupsResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )
}

const defaultProps: OrgAlertsGroupsProps = {
  group: 'repository',
  alertsGroupsPath,
  alertsPath,
  query: defaultQuery,
  cursor: null,
  onStateFilterChange: jest.fn(),
  setCursor: jest.fn(),
}

jest.mock('../../components/AlertListItem', () => ({
  AlertListItem: ({alert}: AlertListItemProps) => {
    return <div role="listitem">{alert.title}</div>
  },
}))

jest.mock('@github-ui/list-view/ListItem', () => ({
  ListItem: ({children}: React.PropsWithChildren) => {
    return <div role="listitem">{children}</div>
  },
}))

jest.mock('@github-ui/list-view/ListItemLeadingContent', () => ({
  ListItemLeadingContent: ({children}: React.PropsWithChildren) => {
    return <div>{children}</div>
  },
}))

const render = async (renderArgs: {numExpectedAlerts: number}, props: Partial<OrgAlertsGroupsProps> = {}) => {
  const view = reactRender(<OrgAlertsGroups {...defaultProps} {...props} />, {wrapper: TestWrapper})

  // Wait for the alerts to load
  await waitFor(() => {
    expect(
      screen.getByRole('list', {
        name: `${renderArgs.numExpectedAlerts} alerts`,
      }),
    ).toBeInTheDocument()
  })

  return view
}

it('renders and paginates', async () => {
  mockDefaultAlertsGroupsRequest()

  const setCursor = jest.fn()
  const {user, rerender} = await render({numExpectedAlerts: 6}, {setCursor})

  expect(
    screen.getByRole('button', {
      name: 'Previous',
    }),
  ).toBeDisabled()

  expect(
    screen.getByRole('button', {
      name: 'Next',
    }),
  ).not.toBeDisabled()

  const list = screen.getByRole('list', {
    name: '6 alerts',
  })

  const nextPageMock = mockFetch.mockRoute(
    `${alertsGroupsPath}?query=${encodeURIComponent(defaultQuery)}&group=repository&after=cursornext`,
    {
      ...defaultGetAlertsGroupsResponse,
      groups: openAlertsGroupsPageTwo,
      nextCursor: '',
      prevCursor: 'cursorprev',
    } satisfies GetAlertsGroupsResponse,
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
  rerender(<OrgAlertsGroups {...defaultProps} cursor={{after: 'cursornext'}} setCursor={setCursor} />)

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
    `${alertsGroupsPath}?query=${encodeURIComponent(defaultQuery)}&group=repository&before=cursorprev`,
    {
      ...defaultGetAlertsGroupsResponse,
      nextCursor: 'cursornext',
      prevCursor: '',
    } satisfies GetAlertsGroupsResponse,
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
  rerender(<OrgAlertsGroups {...defaultProps} cursor={{before: 'cursorprev'}} setCursor={setCursor} />)

  await waitFor(() => {
    expect(within(list).getAllByRole('listitem')).toHaveLength(3)
  })

  expect(prevPageMock).toHaveBeenCalled()
})

it('shows alert lists for the selected group', async () => {
  mockDefaultAlertsGroupsRequest()

  const params = new URLSearchParams()
  params.set('query', 'is:open repo:security-campaigns/test-2')

  mockFetch.mockRoute(`${alertsPath}?${params.toString()}`, defaultGetAlertsResponse, {
    headers: new Headers({
      'Content-Type': 'application/json',
    }),
  })

  const {user} = await render({numExpectedAlerts: 6})

  const alertsMock = mockFetch.mockRoute(
    `${alertsPath}?${params.toString()}`,
    {
      ...defaultGetAlertsResponse,
      alerts: openAlerts,
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
      name: 'Toggle github/security-campaigns-2',
    }),
  )

  const list = screen.getByRole('list', {
    name: '6 alerts',
  })

  await waitFor(() => {
    expect(within(list).getAllByRole('listitem')).toHaveLength(6)
  })

  expect(alertsMock).toHaveBeenCalled()
})

it('expands/collapse alert lists with right and left keyboard arrows', async () => {
  mockFetch.mockRoute(
    `${alertsGroupsPath}?query=${encodeURIComponent(defaultQuery)}&group=repository`,
    defaultGetAlertsGroupsResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const params = new URLSearchParams()
  params.set('query', 'is:open repo:security-campaigns/test-2')

  mockFetch.mockRoute(`${alertsPath}?${params.toString()}`, defaultGetAlertsResponse, {
    headers: new Headers({
      'Content-Type': 'application/json',
    }),
  })

  const {user} = await render({numExpectedAlerts: 6})

  const alertsMock = mockFetch.mockRoute(
    `${alertsPath}?${params.toString()}`,
    {
      ...defaultGetAlertsResponse,
      alerts: openAlerts,
      nextCursor: '',
      prevCursor: 'cursorprev',
    } satisfies GetAlertsResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const toggleButton = screen.getByRole('button', {
    name: 'Toggle github/security-campaigns-2',
  })

  await user.click(toggleButton)
  await user.keyboard('{ArrowLeft}')

  const list = screen.getByRole('list', {
    name: '6 alerts',
  })
  await waitFor(() => {
    expect(within(list).getAllByRole('listitem')).toHaveLength(3)
  })

  await user.keyboard('{ArrowRight}')

  await waitFor(() => {
    expect(within(list).getAllByRole('listitem')).toHaveLength(6)
  })

  expect(alertsMock).toHaveBeenCalled()
})

it('expand alerts by default if campaign contains only one repository', async () => {
  mockFetch.mockRoute(
    `${alertsGroupsPath}?query=${encodeURIComponent(defaultQuery)}&group=repository`,
    singleGetAlertsGroupsResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const params = new URLSearchParams()
  params.set('query', 'is:open repo:security-campaigns/test-1')

  mockFetch.mockRoute(`${alertsPath}?${params.toString()}`, defaultGetAlertsResponse, {
    headers: new Headers({
      'Content-Type': 'application/json',
    }),
  })

  await render({numExpectedAlerts: 5})

  const list = screen.getByRole('list', {
    name: '5 alerts',
  })

  await waitFor(() => {
    expect(within(list).getAllByRole('listitem')).toHaveLength(4)
  })
})

it('closes opened group when switching tabs', async () => {
  mockDefaultAlertsGroupsRequest()

  mockFetch.mockRoute(`${alertsPath}?query=${encodeURIComponent(defaultQuery)}`, defaultGetAlertsResponse, {
    headers: new Headers({
      'Content-Type': 'application/json',
    }),
  })

  const {user, rerender} = await render({numExpectedAlerts: 6})

  mockFetch.mockRoute(
    `${alertsPath}?query=${encodeURIComponent(defaultQuery)}+${encodeURIComponent('repo:security-campaigns/test-2')}`,
    {
      ...defaultGetAlertsResponse,
      alerts: openAlerts,
      nextCursor: '',
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
      name: 'Toggle github/security-campaigns-2',
    }),
  )

  const list = screen.getByRole('list', {
    name: '6 alerts',
  })

  await waitFor(() => {
    expect(within(list).getAllByRole('listitem')).toHaveLength(6)
  })

  mockFetch.mockRoute(
    `${alertsGroupsPath}?query=${encodeURIComponent('is:closed')}&group=repository`,
    defaultGetAlertsGroupsResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  rerender(<OrgAlertsGroups {...defaultProps} query="is:closed" />)

  await waitFor(() => {
    // Expecting to see a listitem for each of the 3 repositories
    expect(within(list).getAllByRole('listitem')).toHaveLength(3)
  })
}, 10000)

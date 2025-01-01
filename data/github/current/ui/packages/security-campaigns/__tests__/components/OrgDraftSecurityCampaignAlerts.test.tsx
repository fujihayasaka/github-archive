import {screen} from '@testing-library/react'
import {render as reactRender} from '@github-ui/react-core/test-utils'
import {
  OrgDraftSecurityCampaignAlerts,
  type OrgDraftSecurityCampaignAlertsProps,
} from '../../components/OrgDraftSecurityCampaignAlerts'
import {mockFetch} from '@github-ui/mock-fetch'
import type {GetAlertsResponse} from '../../types/get-alerts-response'
import {createSecurityCampaignAlert, createSecurityCampaignAlertGroup} from '../../test-utils/mock-data'
import type {GetAlertsGroupsResponse} from '../../types/get-alerts-groups-response'

const defaultProps: OrgDraftSecurityCampaignAlertsProps = {
  query: 'is:open',
  group: 'none',
  organizationLogin: 'github',
  cursor: null,
  onCursorChange: jest.fn(),
  onGroupChange: jest.fn(),
  onStateFilterChange: jest.fn(),
}

const render = async (props: Partial<OrgDraftSecurityCampaignAlertsProps> = {}) =>
  reactRender(<OrgDraftSecurityCampaignAlerts {...defaultProps} {...props} />)

test('It shows the correct alerts if query is not empty and not group by anything', async () => {
  const defaultGetAlertsResponse: GetAlertsResponse = {
    alerts: [
      createSecurityCampaignAlert({number: 1, title: 'Test alert 1'}),
      createSecurityCampaignAlert({number: 2, title: 'Test alert 2'}),
    ],
    openCount: 2,
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

  render({query: 'is:open'})

  const alert1 = await screen.findByText('Test alert 1')
  const alert2 = await screen.findByText('Test alert 2')
  expect(alert1).toBeInTheDocument()
  expect(alert2).toBeInTheDocument()
})

test('It show the correct alert groups when query is not empty and grouped by repository', async () => {
  const defaultGetAlertGroupsResponse: GetAlertsGroupsResponse = {
    groups: [
      createSecurityCampaignAlertGroup({title: 'group-1'}),
      createSecurityCampaignAlertGroup({title: 'group-2'}),
    ],
    openCount: 2,
    closedCount: 1,
    nextCursor: '',
    prevCursor: '',
  }

  mockFetch.mockRoute(
    `/orgs/github/security/alerts/code-scanning/alert-group-list?query=${encodeURIComponent(
      'is:open',
    )}&group=repository`,
    defaultGetAlertGroupsResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  render({query: 'is:open', group: 'repository'})

  const group1 = await screen.findByText('group-1')
  const group2 = await screen.findByText('group-2')
  expect(group1).toBeInTheDocument()
  expect(group2).toBeInTheDocument()
})

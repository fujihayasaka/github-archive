import type {Meta, StoryObj} from '@storybook/react'
import {
  OrgDraftSecurityCampaignAlerts,
  type OrgDraftSecurityCampaignAlertsProps,
} from '../OrgDraftSecurityCampaignAlerts'
import {http, HttpResponse} from 'msw'
import type {GetAlertsResponse} from '../../types/get-alerts-response'
import {createSecurityCampaignAlert, createSecurityCampaignAlertGroup} from '../../test-utils/mock-data'
import type {GetAlertsGroupsResponse} from '../../types/get-alerts-groups-response'

const meta = {
  title: 'Apps/Security Campaigns/Org Draft Security Campaign Alerts',
  component: OrgDraftSecurityCampaignAlerts,
  parameters: {
    msw: {
      handlers: [
        http.get(
          `/orgs/github/security/alerts/code-scanning/alert-group-list?query=${encodeURIComponent(
            'is:open',
          )}&group=repository`,
          () => {
            return HttpResponse.json(mockGetAlertGroupsResponse)
          },
        ),
        http.get('/orgs/github/security/alerts/code-scanning/alert-list', () => {
          return HttpResponse.json(mockGetAlertsResponse)
        }),
      ],
    },
  },
} satisfies Meta<typeof OrgDraftSecurityCampaignAlerts>

export default meta
type Story = StoryObj<typeof OrgDraftSecurityCampaignAlerts>

const defaultArgs: Partial<OrgDraftSecurityCampaignAlertsProps> = {
  query: 'is:open',
  organizationLogin: 'github',
  group: 'none',
  cursor: null,
  onCursorChange: () => {},
  onGroupChange: () => {},
  onStateFilterChange: () => {},
}

const mockGetAlertsResponse: GetAlertsResponse = {
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

const mockGetAlertGroupsResponse: GetAlertsGroupsResponse = {
  groups: [createSecurityCampaignAlertGroup({title: 'group-1'}), createSecurityCampaignAlertGroup({title: 'group-2'})],
  openCount: 2,
  closedCount: 0,
  nextCursor: '',
  prevCursor: '',
}

export const NoGrouping: Story = {
  args: defaultArgs,
  render: (args: OrgDraftSecurityCampaignAlertsProps) => <OrgDraftSecurityCampaignAlerts {...args} />,
}

export const GroupedByRepository: Story = {
  args: {...defaultArgs, group: 'repository'},
  render: (args: OrgDraftSecurityCampaignAlertsProps) => <OrgDraftSecurityCampaignAlerts {...args} />,
}

import {codeScanningOrgAlertListPath, codeScanningOrgAlertGroupListPath} from '@github-ui/paths'
import {CounterLabel} from '@primer/react'
import {OrgAlertsGroups} from './OrgAlertsGroups'
import {OrgAlertsList} from './OrgAlertsList'
import {useMemo} from 'react'
import type {Cursor} from '../types/cursor'
import {AlertsGroupsMenu} from './AlertsGroupsMenu'
import type {AlertsGroup} from '../types/get-alerts-groups-request'

export interface OrgDraftSecurityCampaignAlertsProps {
  query: string
  group: AlertsGroup
  organizationLogin: string
  cursor: Cursor | null
  onCursorChange: (newCursor: Cursor | null) => void
  onGroupChange: (v: AlertsGroup) => void
  onStateFilterChange: (state: 'open' | 'closed') => void
}

export function OrgDraftSecurityCampaignAlerts({
  query,
  group,
  organizationLogin,
  cursor,
  onCursorChange,
  onGroupChange,
  onStateFilterChange,
}: OrgDraftSecurityCampaignAlertsProps) {
  const actions = useMemo(
    () => [{key: 'group-by', render: () => <AlertsGroupsMenu group={group} setGroup={onGroupChange} />}],
    [group, onGroupChange],
  )

  return (
    <>
      {group === 'none' && (
        <OrgAlertsList
          alertsPath={codeScanningOrgAlertListPath({org: organizationLogin})}
          query={query}
          onStateFilterChange={onStateFilterChange}
          cursor={cursor}
          setCursor={onCursorChange}
          actions={actions}
          alertParentLink={{
            kind: 'repository',
          }}
        />
      )}
      {group === 'repository' && (
        <OrgAlertsGroups
          alertsPath={codeScanningOrgAlertListPath({org: organizationLogin})}
          alertsGroupsPath={codeScanningOrgAlertGroupListPath({org: organizationLogin})}
          query={query}
          group={group}
          onStateFilterChange={onStateFilterChange}
          cursor={cursor}
          setCursor={onCursorChange}
          actions={actions}
          alertParentLink={{
            kind: 'repository',
          }}
          renderGroupTrailingBadges={alertGroup =>
            alertGroup.alertCount
              ? [
                  <CounterLabel key={0} className="ml-2">
                    {alertGroup.alertCount}
                  </CounterLabel>,
                ]
              : []
          }
        />
      )}
    </>
  )
}

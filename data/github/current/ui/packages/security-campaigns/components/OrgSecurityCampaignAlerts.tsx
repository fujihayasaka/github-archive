import {useMemo} from 'react'
import type {AlertsGroup} from '../types/get-alerts-groups-request'
import {AlertsGroupsMenu} from './AlertsGroupsMenu'
import {type OrgAlertsGroupsProps, OrgAlertsGroups} from './OrgAlertsGroups'
import {type OrgAlertsListProps, OrgAlertsList} from './OrgAlertsList'

export function OrgSecurityCampaignAlerts({
  group,
  onGroupChange,
  ...props
}: OrgAlertsListProps &
  OrgAlertsGroupsProps & {
    group: AlertsGroup
    onGroupChange: (group: AlertsGroup) => void
  }) {
  const actions = useMemo(
    () => [{key: 'group-by', render: () => <AlertsGroupsMenu group={group} setGroup={onGroupChange} />}],
    [group, onGroupChange],
  )

  if (group === 'none') {
    return <OrgAlertsList {...props} actions={actions} />
  }

  return <OrgAlertsGroups {...props} group={group} actions={actions} alertParentLink={props.alertParentLink} />
}

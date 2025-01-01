import type React from 'react'
import {AlertsList, type AlertsListProps} from './AlertsList'
import {useOrgAlertsQuery} from '../hooks/use-org-alerts-query'
import type {Cursor} from '@github-ui/code-scanning-shared/types/cursor'
import {AlertsListItems} from './AlertsListItems'
import {AlertListItem} from './AlertListItem'
import type {AlertParentLink} from '../types/security-campaign-alert'

export type OrgAlertsListProps = {
  alertsPath: string
  query: string
  onStateFilterChange: (state: 'open' | 'closed') => void
  cursor: Cursor | null
  setCursor: (cursor: Cursor | null) => void
  alertParentLink?: AlertParentLink
  showLimitedAlertsWarning: boolean
} & Pick<AlertsListProps, 'actions'>

export function OrgAlertsList({
  alertsPath,
  query,
  onStateFilterChange,
  cursor,
  setCursor,
  actions,
  alertParentLink,
  showLimitedAlertsWarning,
}: OrgAlertsListProps): React.ReactNode {
  const alertsQuery = useOrgAlertsQuery(alertsPath, {query, cursor})

  return (
    <AlertsList
      openCount={alertsQuery.data?.openCount}
      closedCount={alertsQuery.data?.closedCount}
      prevCursor={alertsQuery.data?.prevCursor}
      nextCursor={alertsQuery.data?.nextCursor}
      isLoading={alertsQuery.isLoading}
      isError={alertsQuery.isError}
      showLimitedAlertsWarning={showLimitedAlertsWarning}
      query={query}
      onStateFilterChange={onStateFilterChange}
      showStateFilters
      onCursorChange={setCursor}
      actions={actions}
    >
      <AlertsListItems
        alerts={alertsQuery.data?.alerts || []}
        query={query}
        isLoading={alertsQuery.isLoading}
        isError={alertsQuery.isError}
        renderAlert={props => <AlertListItem alert={props} alertParentLink={alertParentLink} />}
      />
    </AlertsList>
  )
}

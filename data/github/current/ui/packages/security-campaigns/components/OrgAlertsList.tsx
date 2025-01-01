import type React from 'react'
import {AlertsList, type AlertsListProps} from './AlertsList'
import {useOrgAlertsQuery} from '../hooks/use-org-alerts-query'
import type {AlertsCursor} from '../types/alerts-cursor'
import {AlertsListItems} from './AlertsListItems'
import {AlertListItem} from './AlertListItem'

export type OrgAlertsListProps = {
  alertsPath: string
  alertsGroupsPath: string
  query: string
  onStateFilterChange: (state: 'open' | 'closed') => void
  cursor: AlertsCursor | null
  setCursor: (cursor: AlertsCursor | null) => void
  isCampaignClosed: boolean
} & Pick<AlertsListProps, 'actions'>

export function OrgAlertsList({
  alertsPath,
  query,
  onStateFilterChange,
  cursor,
  setCursor,
  actions,
  isCampaignClosed,
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
        renderAlert={props => <AlertListItem alert={props} showRepository isCampaignClosed={isCampaignClosed} />}
      />
    </AlertsList>
  )
}

import {useState, useCallback, useEffect} from 'react'
import type {AlertsGroup} from '../types/get-alerts-groups-request'
import {AlertsList, type AlertsListProps} from './AlertsList'
import {useOrgAlertsGroupsQuery} from '../hooks/use-org-alerts-groups-query'
import {AlertsListGroups} from './AlertsListGroups'
import {AlertListGroup} from './AlertListGroup'
import type {AlertsCursor} from '../types/alerts-cursor'
import {useOrgAlertsQuery} from '../hooks/use-org-alerts-query'
import {AlertsListItems} from './AlertsListItems'
import {AlertListItem} from './AlertListItem'
import {PrevNextPagination} from './PrevNextPagination'

function RepositoriesAlerts({
  alertsPath,
  query,
  repositories,
}: {
  alertsPath: string
  query: string
  repositories: string[]
}) {
  const scopedQuery = [query, ...repositories.map(repo => `repo:${repo}`)].join(' ')

  const [cursor, setCursor] = useState<AlertsCursor | null>(null)
  const alertsQuery = useOrgAlertsQuery(alertsPath, {query: scopedQuery, cursor})

  return (
    <>
      <AlertsListItems
        alerts={alertsQuery.data?.alerts || []}
        query={query}
        isLoading={alertsQuery.isLoading}
        isError={alertsQuery.isError}
        renderAlert={props => <AlertListItem alert={props} showRepository />}
      />
      <PrevNextPagination
        onCursorChange={setCursor}
        prevCursor={alertsQuery.data?.prevCursor}
        nextCursor={alertsQuery.data?.nextCursor}
      />
    </>
  )
}

export type OrgAlertsGroupsProps = {
  group: AlertsGroup
  alertsPath: string
  alertsGroupsPath: string
  query: string
  onStateFilterChange: (state: 'open' | 'closed') => void
  cursor: AlertsCursor | null
  setCursor: (cursor: AlertsCursor | null) => void
} & Pick<AlertsListProps, 'actions'>

export function OrgAlertsGroups({
  actions,
  alertsGroupsPath,
  alertsPath,
  group,
  query,
  onStateFilterChange,
  cursor,
  setCursor,
}: OrgAlertsGroupsProps): React.ReactNode {
  const expansionKey = `-${group}-${query}-${cursor}`

  const [isExpanded, setIsExpanded] = useState<{[key: string]: boolean}>({})
  const toggleExpanded = useCallback(
    async (expandedGroup: string) => {
      setIsExpanded({
        ...isExpanded,
        [expandedGroup + expansionKey]: !isExpanded[expandedGroup + expansionKey],
      })
    },
    [isExpanded, setIsExpanded, expansionKey],
  )

  const alertsQuery = useOrgAlertsGroupsQuery(alertsGroupsPath, {query, group, cursor})

  useEffect(() => {
    // Check if campaign has only one group and expand it by default
    if (
      alertsQuery.data &&
      !alertsQuery.data.nextCursor &&
      !alertsQuery.data.prevCursor &&
      alertsQuery.data.groups.length === 1 &&
      alertsQuery.data.groups[0]
    ) {
      setIsExpanded({
        [alertsQuery.data.groups[0].title + expansionKey]: true,
      })
    } else {
      setIsExpanded({})
    }
  }, [alertsQuery.data, group, query, cursor, expansionKey])

  return (
    <AlertsList
      openCount={alertsQuery.data?.openCount}
      closedCount={alertsQuery.data?.closedCount}
      prevCursor={alertsQuery.data?.prevCursor}
      nextCursor={alertsQuery.data?.nextCursor}
      isLoading={alertsQuery.isLoading}
      isError={alertsQuery.isError}
      query={query}
      showStateFilters
      onStateFilterChange={onStateFilterChange}
      onCursorChange={setCursor}
      actions={actions}
    >
      <AlertsListGroups
        groups={alertsQuery.data?.groups || []}
        query={query}
        isLoading={alertsQuery.isLoading}
        isError={alertsQuery.isError}
        renderGroup={props => (
          <AlertListGroup
            group={props}
            expanded={isExpanded[props.title + expansionKey] || false}
            onExpandedChange={toggleExpanded}
            renderGroup={({repositories}) => (
              <RepositoriesAlerts repositories={repositories} alertsPath={alertsPath} query={query} />
            )}
          />
        )}
      />
    </AlertsList>
  )
}

import {useState, useCallback, useEffect} from 'react'
import type {AlertsGroup} from '../types/get-alerts-groups-request'
import {AlertsList, type AlertsListProps} from './AlertsList'
import {useOrgAlertsGroupsQuery} from '../hooks/use-org-alerts-groups-query'
import {AlertsListGroups} from './AlertsListGroups'
import {AlertListGroup} from './AlertListGroup'
import type {Cursor} from '../types/cursor'
import {useOrgAlertsQuery} from '../hooks/use-org-alerts-query'
import {AlertsListItems} from './AlertsListItems'
import {AlertListItem} from './AlertListItem'
import {PrevNextPagination} from './PrevNextPagination'
import type {AlertParentLink} from '../types/security-campaign-alert'
import type {SecurityCampaignAlertGroup} from '../types/security-campaign-alert-group'
import type {ListItemTrailingBadge} from '@github-ui/list-view/ListItemTrailingBadge'

function RepositoriesAlerts({
  alertsPath,
  query,
  repositories,
  alertParentLink,
}: {
  alertsPath: string
  query: string
  repositories: string[]
  alertParentLink?: AlertParentLink
}) {
  const scopedQuery = [query, ...repositories.map(repo => `repo:${repo}`)].join(' ')

  const [cursor, setCursor] = useState<Cursor | null>(null)
  const alertsQuery = useOrgAlertsQuery(alertsPath, {query: scopedQuery, cursor})

  return (
    <>
      <AlertsListItems
        alerts={alertsQuery.data?.alerts || []}
        query={query}
        isLoading={alertsQuery.isLoading}
        isError={alertsQuery.isError}
        renderAlert={props => <AlertListItem alert={props} alertParentLink={alertParentLink} />}
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
  cursor: Cursor | null
  setCursor: (cursor: Cursor | null) => void
  alertParentLink: AlertParentLink
  renderGroupMetadata?: (group: SecurityCampaignAlertGroup) => React.ReactNode
  renderGroupTrailingBadges?: (
    group: SecurityCampaignAlertGroup,
  ) => Array<React.ReactElement<typeof ListItemTrailingBadge>>
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
  alertParentLink,
  renderGroupMetadata,
  renderGroupTrailingBadges,
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
            renderMetadata={renderGroupMetadata}
            renderTrailingBadges={renderGroupTrailingBadges}
            renderGroup={({repositories}) => (
              <RepositoriesAlerts
                repositories={repositories}
                alertsPath={alertsPath}
                query={query}
                alertParentLink={alertParentLink}
              />
            )}
            alertParentLink={alertParentLink}
          />
        )}
      />
    </AlertsList>
  )
}

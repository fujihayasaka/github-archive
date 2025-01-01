import {NestingTable} from '@github-ui/role-assignments/nesting-table'
import {RoleAssignmentsTableRow} from '@github-ui/role-assignments/table-row'
import type {ActorRoleAssignment} from '@github-ui/role-assignments/types/actor-role-assignment'
import {testIdProps} from '@github-ui/test-id-props'
import {useSearchParams} from '@github-ui/use-navigate'
import {Button, Pagination} from '@primer/react'
import {RoleAssignmentsBlankslate} from './RoleAssignmentsBlankslate'
import {RoleAssignmentsTableTab} from './RoleAssignmentsTableTab'
import {useRoutingContext} from '../RoutingProvider'
import {RoleAssignmentsFilter} from './RoleAssignmentsFilter'
import {SelectedTab} from '../types/selected-tab'
import {useBannerContext} from '@github-ui/role-assignments/banner-provider'
import {updateSelectedTab} from '../utils/selected-tab-utils'
import {useCallback, useEffect, useState} from 'react'
import {hasNonAssigneeSearchQuery} from '../utils/filter-utils'
import {RoleAssignmentsNoResultsBlankslate} from './RoleAssignmentsNoResultsBlankslate'
import type {FilterQuery} from '@github-ui/filter'

interface RoleAssignmentsTableProps {
  usersCount: number
  teamsCount: number
  roleType: string
  assignments: ActorRoleAssignment[]
  showEnterpriseTeamLabel?: boolean // Show a label for enterprise teams in the table
  hasWriteAccess: boolean
  currentPage?: number
  pageCount?: number
  selectedTab?: SelectedTab
}

export const RoleType = {
  Enterprise: 'enterprise',
  Organization: 'organization',
} as const

export type RoleType = (typeof RoleType)[keyof typeof RoleType]

const actorTypePluralMap: {[key in SelectedTab]: string} = {
  [SelectedTab.User]: 'users',
  [SelectedTab.Team]: 'teams',
}

export function RoleAssignmentsTable({
  usersCount,
  teamsCount,
  roleType,
  assignments,
  hasWriteAccess,
  showEnterpriseTeamLabel = false,
  currentPage = 1,
  pageCount = 1,
  selectedTab = SelectedTab.User,
}: RoleAssignmentsTableProps) {
  const {newRoleAssignmentPath, roleAssignmentsPath} = useRoutingContext()
  const [searchParams] = useSearchParams()
  const querySearchParam = searchParams.get('query') || ''
  const [filterValue, setFilterValue] = useState<string>(querySearchParam)
  useEffect(() => {
    setFilterValue(querySearchParam)
  }, [querySearchParam])

  const {navigate} = useBannerContext()
  const handleSearchSubmit = useCallback(
    (request: FilterQuery) => {
      // preventAutofocus prevents use-navigation-focus from focusing on the h1 so we can keep focus on the filter input
      navigate(roleAssignmentsPath({query: request.raw}), {preventAutofocus: true})
    },
    [roleAssignmentsPath, navigate],
  )
  const handleSearchChange = (value: string) => {
    setFilterValue(value)
  }

  // Show "No roles assigned" blank slate instead of the table if there are no users or teams and there is no filter (excluding selected tab)
  // If there is filter, show the table with internal "No results" blankslate
  const hasFilter = hasNonAssigneeSearchQuery(querySearchParam)
  const showBlankSlate = usersCount === 0 && teamsCount === 0 && !hasFilter

  return (
    <>
      {showBlankSlate ? (
        <RoleAssignmentsBlankslate
          roleType={roleType}
          actorTypePlural="users or teams"
          usePrimaryAction
          hasWriteAccess={hasWriteAccess}
        />
      ) : (
        <div className="d-flex flex-column gap-3">
          <div className="d-flex gap-2">
            <span className="flex-1">
              <RoleAssignmentsFilter
                placeholderText={`Search ${roleType} role assignments`}
                filterValue={filterValue}
                onChange={handleSearchChange}
                onSubmit={handleSearchSubmit}
              />
            </span>
            {hasWriteAccess && (
              <Button variant="primary" onClick={() => navigate(newRoleAssignmentPath())}>
                Assign role
              </Button>
            )}
          </div>
          <NestingTable
            header={
              <div className="d-flex">
                <RoleAssignmentsTableTab
                  title="Users"
                  isSelected={selectedTab === SelectedTab.User}
                  count={usersCount}
                  to={roleAssignmentsPath({
                    query: updateSelectedTab(querySearchParam, SelectedTab.User),
                  })}
                  {...testIdProps(
                    `role-assignments-table-tab-users${selectedTab === SelectedTab.User ? '-selected' : ''}`,
                  )}
                />
                <RoleAssignmentsTableTab
                  title="Teams"
                  isSelected={selectedTab === SelectedTab.Team}
                  count={teamsCount}
                  to={roleAssignmentsPath({
                    query: updateSelectedTab(querySearchParam, SelectedTab.Team),
                  })}
                  {...testIdProps(
                    `role-assignments-table-tab-teams${selectedTab === SelectedTab.Team ? '-selected' : ''}`,
                  )}
                />
              </div>
            }
            {...testIdProps('role-assignments-table')}
          >
            {assignments.length > 0 ? (
              <ul aria-label="List of assignments">
                {assignments.map(assignment => (
                  <RoleAssignmentsTableRow
                    key={assignment.actor.id}
                    showEnterpriseTeamLabel={showEnterpriseTeamLabel}
                    assignment={assignment}
                    hasWriteAccess={hasWriteAccess}
                  />
                ))}
              </ul>
            ) : hasFilter ? (
              // Show no results blankslate if there's a search query
              <RoleAssignmentsNoResultsBlankslate />
            ) : (
              // Show no assignments blankslate if there's no search query
              <RoleAssignmentsBlankslate
                roleType={roleType}
                actorTypePlural={actorTypePluralMap[selectedTab]}
                hasWriteAccess={hasWriteAccess}
              />
            )}
          </NestingTable>
          {pageCount > 1 && (
            <Pagination
              currentPage={currentPage}
              pageCount={pageCount}
              hrefBuilder={page => roleAssignmentsPath({page, query: querySearchParam})}
              {...testIdProps('role-assignment-pagination')}
            />
          )}
        </div>
      )}
    </>
  )
}

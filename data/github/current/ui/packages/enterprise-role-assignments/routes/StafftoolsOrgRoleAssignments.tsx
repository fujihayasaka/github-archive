import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {ActorRoleAssignment} from '@github-ui/role-assignments/types/actor-role-assignment'
import {PageHeader} from '@primer/react'
import {RoleType, RoleAssignmentsTable} from '../components/RoleAssignmentsTable'
import type {SelectedTab} from '../types/selected-tab'
import {RoutingProvider} from '@github-ui/role-assignments/routing-provider'

export interface StafftoolsOrgRoleAssignmentsPayload {
  slug: string
  assignments: ActorRoleAssignment[]
  teamsCount: number
  usersCount: number
  currentPage: number
  pageCount: number
  selectedTab: SelectedTab
}

export function StafftoolsOrgRoleAssignments() {
  const {slug, assignments, teamsCount, usersCount, currentPage, pageCount, selectedTab} =
    useRoutePayload<StafftoolsOrgRoleAssignmentsPayload>()

  return (
    <RoutingProvider slug={slug} ownerType="organization" stafftools>
      <div className="d-flex flex-column">
        <PageHeader>
          <PageHeader.TitleArea>
            <PageHeader.Title as="h1">Organization role assignments</PageHeader.Title>
          </PageHeader.TitleArea>
        </PageHeader>
        <hr />
        <RoleAssignmentsTable
          usersCount={usersCount}
          teamsCount={teamsCount}
          roleType={RoleType.Organization}
          assignments={assignments}
          hasWriteAccess={false}
          currentPage={currentPage}
          pageCount={pageCount}
          selectedTab={selectedTab}
          showEnterpriseTeamLabel
          canViewEnterpriseTeams
        />
      </div>
    </RoutingProvider>
  )
}

import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {ActorRoleAssignment} from '@github-ui/role-assignments/types/actor-role-assignment'
import {PageHeader} from '@primer/react'
import {RoleType, RoleAssignmentsTable} from '../components/RoleAssignmentsTable'
import type {SelectedTab} from '../types/selected-tab'
import {RoutingProvider} from '@github-ui/role-assignments/routing-provider'

export interface EnterpriseRoleAssignmentsPayload {
  slug: string
  assignments: ActorRoleAssignment[]
  teamsCount: number
  usersCount: number
  currentPage: number
  pageCount: number
  hasWriteAccess: boolean
  selectedTab: SelectedTab
  canViewEnterpriseTeams: boolean
}

export function EnterpriseRoleAssignments() {
  const {
    slug,
    assignments,
    teamsCount,
    usersCount,
    currentPage,
    pageCount,
    hasWriteAccess,
    selectedTab,
    canViewEnterpriseTeams,
  } = useRoutePayload<EnterpriseRoleAssignmentsPayload>()
  return (
    <RoutingProvider slug={slug} ownerType="enterprise">
      <div className="d-flex flex-column gap-3">
        <PageHeader className="border-bottom width-full color-border-muted">
          <PageHeader.TitleArea>
            <PageHeader.Title as="h1" className="mb-2">
              Enterprise role assignments
            </PageHeader.Title>
          </PageHeader.TitleArea>
        </PageHeader>
        <RoleAssignmentsTable
          usersCount={usersCount}
          teamsCount={teamsCount}
          roleType={RoleType.Enterprise}
          assignments={assignments}
          hasWriteAccess={hasWriteAccess}
          currentPage={currentPage}
          pageCount={pageCount}
          selectedTab={selectedTab}
          canViewEnterpriseTeams={canViewEnterpriseTeams}
        />
      </div>
    </RoutingProvider>
  )
}

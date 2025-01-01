import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {ActorRoleAssignment} from '@github-ui/role-assignments/types/actor-role-assignment'
import {PageHeader} from '@primer/react'
import {RoleAssignmentsTable, RoleType} from '../components/RoleAssignmentsTable'
import styles from './OrgRoleAssignments.module.css'
import type {SelectedTab} from '../types/selected-tab'
import {RoutingProvider} from '@github-ui/role-assignments/routing-provider'

export interface OrgRoleAssignmentsPayload {
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

export function OrgRoleAssignments() {
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
  } = useRoutePayload<OrgRoleAssignmentsPayload>()

  return (
    <RoutingProvider slug={slug} ownerType="organization">
      <div className="d-flex flex-column gap-3">
        <PageHeader>
          <PageHeader.TitleArea className="pb-1">
            <PageHeader.Title as="h2">Role assignments</PageHeader.Title>
          </PageHeader.TitleArea>
          <PageHeader.Description className={styles.description}>
            Assign teams or people an organization role
          </PageHeader.Description>
        </PageHeader>
        <RoleAssignmentsTable
          usersCount={usersCount}
          teamsCount={teamsCount}
          roleType={RoleType.Organization}
          assignments={assignments}
          showEnterpriseTeamLabel
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

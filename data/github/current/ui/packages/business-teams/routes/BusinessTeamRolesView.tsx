import {newEnterpriseRoleAssignmentPath, enterpriseRoleAssignmentsPath} from '@github-ui/paths'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {BannerProvider} from '@github-ui/role-assignments/banner-provider'
import {NestingTable} from '@github-ui/role-assignments/nesting-table'
import {RoleDetailsRow} from '@github-ui/role-assignments/role-details-row'
import type {ActorBasicMeta, RoleAssignment} from '@github-ui/role-assignments/types/actor-role-assignment'
import type {FgpMetadata} from '@github-ui/role-assignments/types/fgp-metadata'
import {testIdProps} from '@github-ui/test-id-props'
import {IdBadgeIcon} from '@primer/octicons-react'
import {Button} from '@primer/react'
import {Blankslate} from '@primer/react/experimental'
import {BusinessTeamHeaderView} from '../components/BusinessTeamHeaderView'
import styles from '../styles/BusinessTeamRolesView.module.css'
import type {EnterpriseTeam} from '../types'

export interface BusinessTeamRolesViewPayload {
  orgAssignmentsEnabled: boolean
  enterpriseSlug: string
  enterpriseTeam: EnterpriseTeam
  roleAssignments: RoleAssignment[]
  fgps: {[roleId: number]: FgpMetadata}
  viewerPermissions: {[permission: string]: boolean}
}

export function BusinessTeamRolesView() {
  const {orgAssignmentsEnabled, enterpriseSlug, enterpriseTeam, viewerPermissions, roleAssignments, fgps} =
    useRoutePayload<BusinessTeamRolesViewPayload>()

  return (
    <BannerProvider>
      <BusinessTeamHeaderView
        orgAssignmentsEnabled={orgAssignmentsEnabled}
        enterpriseSlug={enterpriseSlug}
        enterpriseTeam={enterpriseTeam}
        currentView="Assigned roles"
      />

      {roleAssignments.length === 0 ? (
        <BlankslateContent
          viewerPermissions={viewerPermissions}
          createAssignmentHref={newEnterpriseRoleAssignmentPath({slug: enterpriseSlug})}
        />
      ) : (
        <AssignedRolesTable
          actor={{
            id: enterpriseTeam.id,
            name: enterpriseTeam.name,
            type: 'BusinessTeam',
            roleAssignmentsPath: enterpriseRoleAssignmentsPath({slug: enterpriseSlug}),
          }}
          roleAssignments={roleAssignments}
          fgps={fgps}
          createAssignmentHref={newEnterpriseRoleAssignmentPath({slug: enterpriseSlug})}
          viewerPermissions={viewerPermissions}
        />
      )}
    </BannerProvider>
  )
}

function BlankslateContent({
  createAssignmentHref,
  viewerPermissions,
}: {
  createAssignmentHref: string
  viewerPermissions: {[permission: string]: boolean}
}) {
  const assignContent = (
    <>
      <Blankslate.Description>You can assign multiple enterprise roles to your team.</Blankslate.Description>
      <div className="mt-4" />
      <Button variant="primary" as="a" href={createAssignmentHref}>
        Assign Enterprise role
      </Button>
    </>
  )

  return (
    <Blankslate spacious>
      <Blankslate.Visual>
        <IdBadgeIcon size={24} className="mb-3" />
      </Blankslate.Visual>
      <Blankslate.Heading>You have no assigned roles</Blankslate.Heading>
      {viewerPermissions['write'] === true && assignContent}
    </Blankslate>
  )
}

interface AssignedRolesTableProps {
  actor: ActorBasicMeta
  roleAssignments: RoleAssignment[]
  fgps: {[roleId: number]: FgpMetadata}
  createAssignmentHref: string
  viewerPermissions: {[permission: string]: boolean}
}
function AssignedRolesTable({
  actor,
  roleAssignments,
  fgps,
  createAssignmentHref,
  viewerPermissions,
}: AssignedRolesTableProps) {
  const header = (
    <div className={styles.tableHeaderContent}>
      <span>Enterprise roles</span>
      {viewerPermissions['write'] === true && (
        <Button variant="primary" as="a" href={createAssignmentHref}>
          Assign Enterprise role
        </Button>
      )}
    </div>
  )

  return (
    <NestingTable header={header} {...testIdProps('role-assignments-table')}>
      <ul aria-label="List of assignments">
        {roleAssignments.map(assignment => {
          // fallback empty obj only for TS checking, in actuality we know that fgps contains an entry for all roles assigned
          // per enterprise_team_role_assignments_controller payload
          const fgpsForRole = fgps[assignment.role.id] || {Enterprise: {}, Organization: {}, Repository: {}}
          return (
            <RoleDetailsRow
              key={assignment.role.id}
              actor={actor}
              role={assignment.role}
              fgpMetadata={fgpsForRole}
              viewerPermissions={viewerPermissions}
            />
          )
        })}
      </ul>
    </NestingTable>
  )
}

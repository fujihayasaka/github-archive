import {testIdProps} from '@github-ui/test-id-props'
import {InfoIcon, KebabHorizontalIcon, XIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu} from '@primer/react'
import {useState, useRef} from 'react'
import {NestingTableRow} from './NestingTable/NestingTableRow'
import {RemoveRoleAssignmentDialog} from './RemoveRoleAssignmentDialog'
import {RoleFgpsDialog} from './RoleFgpsDialog'
import type {ActorBasicMeta, Role} from '../types/ActorRoleAssignment'
import type {FgpMetadata} from '../types/FgpMetadata'
import getRoleIcon from '../utils/RoleIconMap'
import styles from './RoleDetailsRow.module.css'

export function RoleDetailsRow({
  actor,
  role,
  fgpMetadata,
  viewerPermissions,
}: {
  actor: ActorBasicMeta
  role: Role
  fgpMetadata: FgpMetadata
  viewerPermissions: {[permission: string]: boolean}
}) {
  return (
    <NestingTableRow
      leadingIcon={
        <span className="fgColor-muted" {...testIdProps('role-icon')}>
          {getRoleIcon(role.octicon)}
        </span>
      }
      title={role.name}
      description={<span>{role.description}</span>}
      trailingItems={[
        <RoleActionMenu
          key={`actions-role-${role.id}`}
          actor={actor}
          role={role}
          fgpMetadata={fgpMetadata}
          viewerPermissions={viewerPermissions}
        />,
      ]}
    />
  )
}

function RoleActionMenu({
  actor,
  role,
  fgpMetadata,
  viewerPermissions,
}: {
  actor: ActorBasicMeta
  role: Role
  fgpMetadata: FgpMetadata
  viewerPermissions: {[permission: string]: boolean}
}) {
  const [showDetails, setShowDetails] = useState(false)
  const [showRemoveDialog, setShowRemoveDialog] = useState(false)
  const menuRef = useRef<HTMLButtonElement>(null)

  const removeContent = (
    <>
      <ActionList.Divider />
      <ActionList.Item variant="danger" onSelect={() => setShowRemoveDialog(true)}>
        <ActionList.LeadingVisual>
          <XIcon />
        </ActionList.LeadingVisual>
        Remove
      </ActionList.Item>
    </>
  )

  return (
    <>
      <ActionMenu anchorRef={menuRef}>
        <ActionMenu.Button
          className={styles.actionMenuButton}
          variant="invisible"
          aria-label={`Actions for ${role.name}`}
          trailingAction={null} // do not want menu triangle indicator, which is included by default
          ref={menuRef}
          {...testIdProps('role-action-menu')}
        >
          <KebabHorizontalIcon />
        </ActionMenu.Button>
        <ActionMenu.Overlay>
          <ActionList>
            <ActionList.Item onSelect={() => setShowDetails(true)}>
              <ActionList.LeadingVisual>
                <InfoIcon />
              </ActionList.LeadingVisual>
              Details
            </ActionList.Item>
            {viewerPermissions.write && removeContent}
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>

      <RoleFgpsDialog
        roleId={role.id}
        title={role.name}
        subtitle={role.description}
        fgpMetadata={fgpMetadata}
        show={showDetails}
        onClose={() => setShowDetails(false)}
        returnFocusRef={menuRef}
      />
      {viewerPermissions.write && showRemoveDialog && (
        <RemoveRoleAssignmentDialog
          actor={actor}
          roleId={role.id}
          roleName={role.name}
          setOpen={setShowRemoveDialog}
          returnFocusRef={menuRef}
          canViewEnterpriseTeams
        />
      )}
    </>
  )
}

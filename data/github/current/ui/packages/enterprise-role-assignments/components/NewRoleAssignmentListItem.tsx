import {clsx} from 'clsx'
import {enterprisePath, orgHovercardPath} from '@github-ui/paths'
import {Link} from '@github-ui/react-core/link'
import {RoleFgpsDialog} from '@github-ui/role-assignments/role-fgps-dialog'
import getRoleIcon from '@github-ui/role-assignments/utils/icon-map'
import {testIdProps} from '@github-ui/test-id-props'
import {InfoIcon, AlertFillIcon} from '@primer/octicons-react'
import {Stack, ActionList, Link as PrimerLink, AvatarStack, Text} from '@primer/react'
import {useState} from 'react'
import styles from './NewRoleAssignmentListItem.module.css'
import type {EnterpriseOrg, Role, RoleStatus} from '../enterprise-role-assignments-types'
import {isEsm} from '../utils/role-utils'
import {GitHubAvatar} from '@github-ui/github-avatar'

export interface NewRoleAssignmentListItemProps {
  role: Role
  roleStatus: RoleStatus | null
  enterpriseOrgs?: EnterpriseOrg[]
  selected: boolean
  onSelectCallback: (roleId: number) => void
}

export function NewRoleAssignmentListItem({
  role,
  roleStatus,
  enterpriseOrgs,
  selected,
  onSelectCallback,
}: NewRoleAssignmentListItemProps) {
  const [showFgpMetadata, setShowFgpMetadata] = useState(false)
  const hasDescriptionContent = role.description || role.enterpriseOwner
  const roleDisabled = roleStatus?.status === 'disabled'
  const isEsmRole = isEsm(role)

  const handleSelectItem = () => {
    if (roleDisabled) return
    onSelectCallback(role.id)
  }

  return (
    <ActionList.Item
      className={clsx(
        styles.listItem,
        !hasDescriptionContent && styles.itemWoDescription,
        roleDisabled && styles.roleDisabled,
      )}
      key={role.name}
      role="menuitemradio"
      selected={selected}
      onSelect={handleSelectItem}
      {...testIdProps(`role-assignment-list-item-${role.name}`)}
    >
      <ActionList.LeadingVisual className={styles.roleIcon} {...testIdProps('role-icon')}>
        {getRoleIcon(role.icon)}
      </ActionList.LeadingVisual>
      <span className={styles.listItemContentTitle}>{role.name}</span>
      {hasDescriptionContent && (
        <ActionList.Description variant="block">
          <Stack gap="none">
            <Stack gap="condensed" direction="horizontal" align="center">
              {isEsmRole && enterpriseOrgs && (
                <AvatarStack disableExpand data-testid="enterprise-orgs-avatarstack">
                  {enterpriseOrgs.map((org, index) => (
                    <GitHubAvatar
                      data-testid="enterprise-org-avatar"
                      key={`${org.displayLogin}_${index + 1}`}
                      src={org.avatarURL}
                      alt={org.displayLogin}
                      data-hovercard-url={orgHovercardPath({owner: org.displayLogin})}
                      square
                    />
                  ))}
                </AvatarStack>
              )}
              <div>
                {role.enterpriseOwner && <EnterpriseOwnedRoleContent {...role.enterpriseOwner} />}
                {role.enterpriseOwner && role.description && <span>{' • '}</span>}
                {isEsmRole && <Text weight="medium">Grants access to all organizations • </Text>}
                {role.description && <span>{role.description}</span>}
              </div>
            </Stack>
            {roleDisabled && (
              <div className={styles.roleWarning}>
                <AlertFillIcon size={12} /> {roleStatus.statusText}
              </div>
            )}
          </Stack>
        </ActionList.Description>
      )}
      <ActionList.TrailingAction
        className={styles.roleInfo}
        label={`Info about ${role.name}`}
        icon={InfoIcon}
        onClick={(e: React.MouseEvent) => {
          e.stopPropagation() // prevent ActionList.Item `onSelect` trigger, b/c this is a click within the item
          setShowFgpMetadata(true)
        }}
        {...testIdProps('info-icon')}
      />
      {/* by wrapping dialog in a div with a custom onClick of `stopPropagation`, we prevent ActionList.Item `onSelect` trigger when interacting w/ dialog.
          With this wrapper hack, we do incur some linting errors to disable
          OK with disabling jsx-a11y/click-events-have-key-events, because key events to escape dialog still work fine. Not actually adding any functionality that a keyboard also would need to do.
          OK with disabling jsx-a11y/no-static-element-interactions, because we don't actually want the div to be interactive.
          OK with disabling prettier/prettier to have the element definition on one line and thus be able to eslint-disable for just one line.
       */}
      {/* eslint-disable-next-line jsx-a11y/click-events-have-key-events, jsx-a11y/no-static-element-interactions, prettier/prettier */}
      <div onClick={(e: React.MouseEvent) => { e.stopPropagation() }}>
        <RoleFgpsDialog
          roleId={role.id}
          title={role.name}
          subtitle={role.description}
          fgpMetadata={role.fgpMetadata}
          show={showFgpMetadata}
          onClose={() => {
            setShowFgpMetadata(false)
          }}
        />
      </div>
    </ActionList.Item>
  )
}

function EnterpriseOwnedRoleContent(props: {name: string; slug: string}) {
  return (
    <span {...testIdProps('enterprise-owned-role')}>
      Role managed by{' '}
      <PrimerLink as={Link} to={enterprisePath({slug: props.slug})} target="_blank" inline>
        {props.name}
      </PrimerLink>
    </span>
  )
}

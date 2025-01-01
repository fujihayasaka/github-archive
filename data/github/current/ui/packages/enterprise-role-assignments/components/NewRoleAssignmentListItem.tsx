import {clsx} from 'clsx'
import {enterprisePath} from '@github-ui/paths'
import {Link} from '@github-ui/react-core/link'
import {RoleFgpsDialog} from '@github-ui/role-assignments/role-fgps-dialog'
import type {FgpMetadata} from '@github-ui/role-assignments/types/fgp-metadata'
import getRoleIcon from '@github-ui/role-assignments/utils/icon-map'
import {testIdProps} from '@github-ui/test-id-props'
import {InfoIcon} from '@primer/octicons-react'
import {ActionList, Link as PrimerLink} from '@primer/react'
import {useState} from 'react'
import styles from './NewRoleAssignmentListItem.module.css'

export interface Role {
  id: number
  name: string
  description: string | null
  icon: string
  fgpMetadata: FgpMetadata
  enterpriseOwner?: {
    slug: string
    name: string
  }
}

export interface NewRoleAssignmentListItemProps {
  role: Role
  selected: boolean
  onSelectCallback: (roleId: number) => void
}

export function NewRoleAssignmentListItem(props: NewRoleAssignmentListItemProps) {
  const [showFgpMetadata, setShowFgpMetadata] = useState(false)
  const hasDescriptionContent = props.role.description || props.role.enterpriseOwner

  return (
    <ActionList.Item
      className={clsx(styles.listItem, !hasDescriptionContent && styles.itemWoDescription)}
      key={props.role.name}
      role="menuitemradio"
      selected={props.selected}
      onSelect={() => props.onSelectCallback(props.role.id)}
      {...testIdProps(`role-assignment-list-item-${props.role.name}`)}
    >
      <ActionList.LeadingVisual className={styles.roleIcon} {...testIdProps('role-icon')}>
        {getRoleIcon(props.role.icon)}
      </ActionList.LeadingVisual>
      <span className={styles.listItemContentTitle}>{props.role.name}</span>
      {hasDescriptionContent && (
        <ActionList.Description variant="block">
          {props.role.enterpriseOwner && <EnterpriseOwnedRoleContent {...props.role.enterpriseOwner} />}
          {props.role.enterpriseOwner && props.role.description && <span>{' • '}</span>}
          {props.role.description && <span>{props.role.description}</span>}
        </ActionList.Description>
      )}
      <ActionList.TrailingAction
        className={styles.roleInfo}
        label={`Info about ${props.role.name}`}
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
          roleId={props.role.id}
          title={props.role.name}
          subtitle={props.role.description}
          fgpMetadata={props.role.fgpMetadata}
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

import {GlobeIcon, NoteIcon} from '@primer/octicons-react'
import {Dialog} from '@primer/react'
import {FgpScopes, type FgpMetadata, type ScopeMetadata} from '../types/FgpMetadata'
import styles from './RoleFgpsDialog.module.css'

export interface RoleFgpsDialogProps {
  roleId: number
  title: string
  subtitle: string | null
  /* fgpMetadata example:
    {
      'Enterprise': { 'category1': ['permissionA', 'permissionB'], 'category2': ['permissionC'] },
      'Organization': { 'category3': ['permissionD']] },
      'Repository': { 'category4': ['permissionE', 'category5': ['permissionF'] },
    }
  */
  fgpMetadata: FgpMetadata
  show: boolean
  onClose: () => void
}

export function RoleFgpsDialog(props: RoleFgpsDialogProps) {
  return (
    props.show && (
      <Dialog
        role={'dialog'}
        title={props.title}
        subtitle={props.subtitle}
        onClose={props.onClose}
        footerButtons={[{content: 'Close', onClick: props.onClose}]}
      >
        <div>
          {emptyFgpMetadata(props.fgpMetadata) ? (
            <div>No permissions have been added to this role.</div>
          ) : (
            Object.values(FgpScopes).map(
              scope => props.fgpMetadata[scope] && scopeSection(props.roleId, scope, props.fgpMetadata[scope]),
            )
          )}
        </div>
      </Dialog>
    )
  )
}

function emptyFgpMetadata(fgpMetadata: FgpMetadata) {
  const noFgpMetadata = fgpMetadata === undefined || Object.keys(fgpMetadata).length === 0
  if (noFgpMetadata) {
    return true
  }

  // case of fgpMetadata having no permission categories for any scopes, even if scopes are defined
  // e.g. { 'Enterprise': {}, 'Organization': {}, 'Repository': {} }
  const noFgps = Object.values(FgpScopes).every(
    scope => fgpMetadata[scope] === undefined || Object.keys(fgpMetadata[scope]).length === 0,
  )

  return noFgps
}

// renders heirarchical display of: scope + icon, the categories of permissions role has within the scope, and indiidual permissions role has under each category
// renders nothing if there are no permissions for the scope
function scopeSection(roleId: number, scope: string, scopeMetadata: ScopeMetadata) {
  // case of scope being defined but not having any permission categories
  // e.g. 'Enterprise' = {}
  if (Object.keys(scopeMetadata).length === 0) {
    return null
  }

  return (
    <div key={`${roleId}-${scope}-fgps`} className={styles.scopeInfo}>
      <div className={styles.scopeHeader}>
        {scopeIcon(scope)}
        <span className={styles.scopeName}>{scope}</span>
      </div>
      {Object.keys(scopeMetadata).map(category => (
        <div key={`${roleId}-${scope}-${category}`} className={styles.categoryInfo}>
          <span>{category}</span>
          <ul className={styles.permissionInfo}>
            {scopeMetadata[category] &&
              scopeMetadata[category].map(permission => (
                <li key={`${roleId}-${scope}-${category}-${permission}`}>{permission}</li>
              ))}
          </ul>
        </div>
      ))}
    </div>
  )
}

// will need to be updated when organization and repo permissions can be assigned
function scopeIcon(scope: string) {
  switch (scope) {
    case 'Enterprise':
      return <GlobeIcon />
    default:
      return <NoteIcon />
  }
}

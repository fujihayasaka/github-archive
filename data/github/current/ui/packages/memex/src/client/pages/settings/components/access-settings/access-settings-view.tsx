import {testIdProps} from '@github-ui/test-id-props'
import {Heading} from '@primer/react'

import {ViewerPrivileges} from '../../../../helpers/viewer-privileges'
import {Origin404Redirect} from '../../../../routes'
import styles from './access-settings-view.module.css'
import {AddCollaborators} from './add-collaborators'
import {CollaboratorsFilterProvider} from './collaborators-filter'
import {CollaboratorsTable} from './collaborators-table'
import {PrivacySettings} from './privacy-settings'

export const AccessSettingsView = () => {
  const {hasAdminPermissions} = ViewerPrivileges()

  if (hasAdminPermissions) {
    return (
      <div className={styles.Box} {...testIdProps('access-settings')}>
        <Heading as="h2" className={styles.Heading}>
          Who has access
        </Heading>
        <PrivacySettings />
        <AddCollaborators />
        <CollaboratorsFilterProvider>
          <CollaboratorsTable />
        </CollaboratorsFilterProvider>
      </div>
    )
  }

  return <Origin404Redirect />
}

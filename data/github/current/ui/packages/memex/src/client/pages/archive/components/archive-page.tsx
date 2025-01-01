import {testIdProps} from '@github-ui/test-id-props'

import {BaseSettingsPage} from '../../../components/base-settings-page'
import {useBindMemexToDocument} from '../../../hooks/use-bind-memex-to-document'
import {useEnabledFeatures} from '../../../hooks/use-enabled-features'
import {ArchivedItemsProvider} from '../archive-page-provider'
import styles from './archive-page.module.css'
import {ArchiveView} from './archive-view'
import {PaginatedArchiveView} from './paginated-archive-view'

export function ArchivePage() {
  useBindMemexToDocument()

  const {memex_table_without_limits} = useEnabledFeatures()
  if (memex_table_without_limits) {
    return (
      <BaseSettingsPage {...testIdProps('paginated-archive-page')} className={styles.BaseSettingsPage}>
        <PaginatedArchiveView />
      </BaseSettingsPage>
    )
  }
  return (
    <BaseSettingsPage {...testIdProps('archive-page')} className={styles.BaseSettingsPage}>
      <ArchivedItemsProvider>
        <ArchiveView />
      </ArchivedItemsProvider>
    </BaseSettingsPage>
  )
}

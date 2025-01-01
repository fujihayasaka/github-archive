import {ArchiveIcon} from '@primer/octicons-react'
import {Spinner} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {memo} from 'react'

import {Blankslate} from '../../../../components/common/blankslate'
import styles from './archive-empty-states.module.css'

export const NoArchivedItems = memo(function NoArchivedItems() {
  return (
    <Blankslate className={styles.Blankslate}>
      <Octicon icon={ArchiveIcon} size={30} className={styles.Octicon} />
      <h2>There aren&apos;t any archived items</h2>
      <p className={styles.Octicon}>Archive items from a project view and they&apos;ll be shown here.</p>
    </Blankslate>
  )
})
export const NoFilteredItems = memo(function NoFilteredItems() {
  return (
    <Blankslate className={styles.Blankslate}>
      <Octicon icon={ArchiveIcon} size={30} className={styles.Octicon} />
      <h2>No results matched your filter</h2>
    </Blankslate>
  )
})
export const Loader = memo(function Loader() {
  return (
    <Blankslate className={styles.Blankslate}>
      <Spinner />
    </Blankslate>
  )
})

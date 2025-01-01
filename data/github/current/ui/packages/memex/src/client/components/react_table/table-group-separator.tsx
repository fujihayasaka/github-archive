import {memo} from 'react'

import {GROUP_SEPARATOR_HEIGHT} from './constants'
import styles from './table-group-separator.module.css'

export const TableGroupSeparator = memo(function TableGroupSeparator() {
  return <div style={{height: `${GROUP_SEPARATOR_HEIGHT}px`}} className={styles.Box} />
})

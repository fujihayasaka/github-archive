import {testIdProps} from '@github-ui/test-id-props'
import {clsx} from 'clsx'
import type {ReactNode} from 'react'

import {useListViewVariant} from '../ListView/VariantContext'
import styles from './MainContent.module.css'

export function ListItemMainContent({children}: {children?: ReactNode}) {
  const {variant} = useListViewVariant()

  return (
    <>
      <div {...testIdProps('list-view-item-main-content')} className={styles.container}>
        <div className={clsx(styles.inner, variant === 'compact' && styles.compact)}>{children}</div>
      </div>
    </>
  )
}

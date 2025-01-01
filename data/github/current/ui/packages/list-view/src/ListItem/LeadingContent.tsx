import {testIdProps} from '@github-ui/test-id-props'
import {clsx} from 'clsx'
import type {PropsWithChildren} from 'react'

import {useListViewSelection} from '../ListView/SelectionContext'
import type {StylableProps} from '../types'
import styles from './LeadingContent.module.css'

export const ListItemLeadingContent = ({style, className, children}: PropsWithChildren<StylableProps>) => {
  const {isSelectable} = useListViewSelection()

  return (
    <div
      className={clsx(styles.container, isSelectable && styles.isSelectable, className)}
      {...testIdProps('list-view-item-leading-content')}
      style={style}
    >
      {children}
    </div>
  )
}

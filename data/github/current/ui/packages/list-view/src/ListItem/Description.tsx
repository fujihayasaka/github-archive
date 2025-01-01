import {testIdProps} from '@github-ui/test-id-props'
import {clsx} from 'clsx'

import {useListViewVariant} from '../ListView/VariantContext'
import type {StylableProps} from '../types'
import styles from './Description.module.css'

interface ListItemDescriptionProps extends StylableProps {
  children?: React.ReactNode
}

export function ListItemDescription({children, style, className}: ListItemDescriptionProps) {
  const {variant} = useListViewVariant()

  return (
    <div
      {...testIdProps('list-view-item-description')}
      className={clsx(styles.container, variant === 'compact' && styles.compact, className)}
      style={style}
    >
      {children}
    </div>
  )
}

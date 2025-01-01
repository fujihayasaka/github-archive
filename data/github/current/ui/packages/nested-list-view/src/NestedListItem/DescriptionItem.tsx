import {testIdProps} from '@github-ui/test-id-props'
import {clsx} from 'clsx'

import styles from './DescriptionItem.module.css'

export function NestedListItemDescriptionItem({children, className, ...props}: React.ComponentProps<'div'>) {
  return (
    <div className={clsx(styles.container, className)} {...testIdProps('list-view-item-descriptionitem')} {...props}>
      {children}
    </div>
  )
}

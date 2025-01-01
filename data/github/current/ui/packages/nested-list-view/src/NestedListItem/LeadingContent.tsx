import {testIdProps} from '@github-ui/test-id-props'
import {clsx} from 'clsx'
import type {PropsWithChildren} from 'react'

import styles from './LeadingContent.module.css'

export type NestedListItemLeadingContentProps = {
  className?: string
}

export function NestedListItemLeadingContent({
  children,
  className,
}: PropsWithChildren<NestedListItemLeadingContentProps>) {
  return (
    <div className={clsx(styles.container, className)} {...testIdProps('nested-list-view-item-leading-content')}>
      {children}
    </div>
  )
}

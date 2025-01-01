import {testIdProps} from '@github-ui/test-id-props'
import {type BetterSystemStyleObject, Box} from '@primer/react'
import {clsx} from 'clsx'
import type {PropsWithChildren} from 'react'

import styles from './LeadingContent.module.css'

export type NestedListItemLeadingContentProps = {
  sx?: BetterSystemStyleObject
  className?: string
}

export function NestedListItemLeadingContent({
  sx,
  children,
  className,
}: PropsWithChildren<NestedListItemLeadingContentProps>) {
  return (
    <Box
      className={clsx(styles.container, className)}
      sx={sx}
      {...testIdProps('nested-list-view-item-leading-content')}
    >
      {children}
    </Box>
  )
}

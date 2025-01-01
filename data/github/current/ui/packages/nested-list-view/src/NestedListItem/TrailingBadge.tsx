import {testIdProps} from '@github-ui/test-id-props'
import {Label, type LabelProps} from '@primer/react'
import {clsx} from 'clsx'
import {type PropsWithChildren, useRef} from 'react'

import {useSuppressActions} from './hooks/use-suppress-actions'
import styles from './TrailingBadge.module.css'

export type NestedListItemTrailingBadgeProps = PropsWithChildren<Pick<LabelProps, 'variant' | 'size'>> & {
  /**
   * Text that is shown as a visible Primer Label and as visually hidden text for screen readers.
   */
  title?: string

  /** Container class name. */
  className?: string
}

export const NestedListItemTrailingBadge = ({
  title,
  className,
  children,
  ...props
}: NestedListItemTrailingBadgeProps) => {
  const trailingBadgesContainerRef = useRef<HTMLDivElement>(null)

  useSuppressActions(trailingBadgesContainerRef)

  return (
    <div
      {...testIdProps('nested-list-view-item-trailing-badge')}
      className={clsx(styles.container, className)}
      aria-hidden
      ref={trailingBadgesContainerRef}
    >
      {children || (
        <Label className={styles.label} {...props}>
          <span className={styles.title}>{title}</span>
        </Label>
      )}
    </div>
  )
}

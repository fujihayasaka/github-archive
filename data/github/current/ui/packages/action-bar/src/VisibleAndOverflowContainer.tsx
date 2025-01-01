import {testIdProps} from '@github-ui/test-id-props'
import {FocusKeys} from '@primer/behaviors'
import {useFocusZone} from '@primer/react'
import {clsx} from 'clsx'
import type {CSSProperties, PropsWithChildren} from 'react'

import {useActionBarContent} from './ActionBarContentContext'
import {useActionBarRef} from './ActionBarRefContext'
import {useActionBarResize} from './ActionBarResizeContext'
import {OverflowMenu, type OverflowMenuProps} from './OverflowMenu'
import styles from './VisibleAndOverflowContainer.module.css'
import {VisibleItems} from './VisibleItems'

export type VisibleAndOverflowContainerProps = PropsWithChildren<{
  overflowMenuToggleProps?: OverflowMenuProps['anchorProps']
  className?: string
  style?: CSSProperties
}>

export const VisibleAndOverflowContainer = ({
  overflowMenuToggleProps,
  children,
  ...props
}: VisibleAndOverflowContainerProps) => {
  const {outerContainerRef} = useActionBarRef()
  const {label, variant, gap} = useActionBarContent()
  const {justifySpaceBetween} = useActionBarResize()

  useFocusZone(
    {
      containerRef: outerContainerRef,
      bindKeys: FocusKeys.ArrowHorizontal | FocusKeys.HomeAndEnd,
      focusOutBehavior: 'wrap',
      disabled: variant !== 'toolbar',
    },
    [outerContainerRef],
  )

  return (
    <div
      ref={outerContainerRef}
      {...testIdProps('action-bar-container')}
      role={variant === 'toolbar' ? 'toolbar' : undefined}
      aria-label={variant === 'toolbar' ? label : undefined}
      style={{gap}}
      className={clsx(styles.Box_0, justifySpaceBetween && styles.space)}
    >
      <VisibleItems {...props} />
      {children}
      <OverflowMenu anchorProps={overflowMenuToggleProps} />
    </div>
  )
}

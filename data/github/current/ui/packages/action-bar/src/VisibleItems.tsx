import {testIdProps} from '@github-ui/test-id-props'
import {clsx} from 'clsx'
import type {CSSProperties} from 'react'

import {useActionBarContent} from './ActionBarContentContext'
import {useActionBarRef} from './ActionBarRefContext'
import {useActionBarResize} from './ActionBarResizeContext'
import {VisibleItem} from './VisibleItem'
import styles from './VisibleItems.module.css'

export const VisibleItems = ({className, style}: {className?: string; style?: CSSProperties}) => {
  const {itemContainerRef} = useActionBarRef()
  const {actions, gap} = useActionBarContent()
  const {visibleChildEndIndex} = useActionBarResize()
  const visibleActions = actions?.slice(0, visibleChildEndIndex)

  return (
    <div
      {...testIdProps('action-bar')}
      ref={itemContainerRef}
      className={clsx(className, styles.Box_1)}
      style={{gap, ...style}}
    >
      {visibleActions?.map(({key, render}) => (
        <VisibleItem key={key} actionKey={key}>
          {render(false)}
        </VisibleItem>
      ))}
    </div>
  )
}

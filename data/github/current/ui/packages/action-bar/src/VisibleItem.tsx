import {testIdProps} from '@github-ui/test-id-props'
import {useIsomorphicLayoutEffect} from '@primer/react'
import {type PropsWithChildren, useRef} from 'react'

import {useActionBarResize} from './ActionBarResizeContext'
import styles from './VisibleItem.module.css'

type VisibleItemProps = PropsWithChildren<{actionKey: string}>

export const VisibleItem = ({children, actionKey: key}: VisibleItemProps) => {
  const itemRef = useRef<HTMLDivElement>(null)
  const {recalculateItemSize} = useActionBarResize()

  useIsomorphicLayoutEffect(() => {
    if (itemRef.current) recalculateItemSize(key, itemRef.current)
  }, [itemRef, recalculateItemSize, key])

  return (
    <div {...testIdProps(`action-bar-item-${key}`)} data-action-bar-item={key} ref={itemRef} className={styles.Box_0}>
      {children}
    </div>
  )
}

import {memo, useMemo, useRef} from 'react'

import useIsVisible from '../../../../components/board/hooks/use-is-visible'
import styles from './archive-list-item.module.css'

export const ArchiveListItem = memo<React.PropsWithChildren>(function ArchiveListItem({children}) {
  const ref = useRef(null)
  const {isVisible, size} = useIsVisible({ref})

  return (
    <li
      style={useMemo(() => ({height: isVisible ? 'unset' : size, flexShrink: 0}), [isVisible, size])}
      ref={ref}
      className={styles.Box}
    >
      {isVisible ? children : null}
    </li>
  )
})

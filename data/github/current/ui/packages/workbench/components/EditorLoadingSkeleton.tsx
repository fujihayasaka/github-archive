import {SkeletonAvatar, SkeletonText} from '@primer/react/experimental'
import {clsx} from 'clsx'

import styles from './EditorLoadingSkeleton.module.css'

export function EditorLoadingSkeleton({fadeIn = false}: {fadeIn?: boolean}) {
  const lineWidths = [50, 60, 70]
  return (
    <div className={clsx(styles.container, fadeIn && styles.fadeIn)}>
      {lineWidths.map(width => (
        <div key={width} className={styles.line}>
          <SkeletonAvatar square size={14} className={styles.lineNumber} />
          <div style={{width: `${width}%`}}>
            <SkeletonText lines={1} />
          </div>
        </div>
      ))}
    </div>
  )
}

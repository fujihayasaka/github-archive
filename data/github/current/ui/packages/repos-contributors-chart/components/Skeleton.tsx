import type {FC} from 'react'
import {SkeletonBox, SkeletonText} from '@primer/react/experimental'
import styles from './Skeleton.module.css'

export const Skeleton: FC = () => {
  return (
    <div className="Box width-full">
      <div className="m-3">
        <div className="width-full d-flex flex-column gap-1 mb-2">
          <SkeletonText size="titleMedium" className={styles.title} />
          <SkeletonText size="bodySmall" className={styles.subtitle} />
        </div>
        <SkeletonBox className={`${styles.mainChart} rounded-2`} />
      </div>
    </div>
  )
}

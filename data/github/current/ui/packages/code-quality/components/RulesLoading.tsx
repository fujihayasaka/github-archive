import {LoadingSkeleton} from '@github-ui/skeleton/LoadingSkeleton'
import styles from './RulesLoading.module.css'
import {randomLabelWidth} from '../utils/random-label-width'

export function RulesLoading({rowCount}: {rowCount: number}): JSX.Element {
  return (
    <>
      {Array.from(Array(rowCount).keys()).map(index => (
        <div className={styles.rowLoading} key={index}>
          <LoadingSkeleton variant="elliptical" height="md" width="md" />
          <div className={styles.skeletonColumn}>
            <LoadingSkeleton variant="rounded" height="sm" width={randomLabelWidth()} />
          </div>
        </div>
      ))}
    </>
  )
}

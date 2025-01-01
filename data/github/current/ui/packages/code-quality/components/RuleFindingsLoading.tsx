import {LoadingSkeleton} from '@github-ui/skeleton/LoadingSkeleton'
import styles from './RuleFindingsLoading.module.css'
import {randomLabelWidth} from '../utils/random-label-width'

export function RuleFindingsLoading({rowCount}: {rowCount: number}): JSX.Element {
  const codeLines = 7
  return (
    <>
      {Array.from({length: rowCount}, (_, index) => (
        <div className={styles.findingContainer} key={index}>
          <div className={styles.headerContainer}>
            <LoadingSkeleton variant="elliptical" height="md" width="md" />
            <div className={styles.headerContent}>
              <LoadingSkeleton variant="rounded" height="sm" width={randomLabelWidth()} />
            </div>
          </div>

          <div className={styles.codeContainer}>
            {Array.from(Array(codeLines).keys()).map(i => (
              <div className={styles.codeLine} key={`${index}-${i}`}>
                <LoadingSkeleton variant="rounded" height="sm" width="2%" />
                <LoadingSkeleton variant="rounded" height="sm" width={randomLabelWidth()} />
              </div>
            ))}
          </div>
        </div>
      ))}
    </>
  )
}

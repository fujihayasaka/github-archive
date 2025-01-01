import {testIdProps} from '@github-ui/test-id-props'
import {useNamedColor} from '@github-ui/use-named-color'
import {ProgressBar} from '@primer/react'
import {clsx} from 'clsx'

import styles from './progress-bar.module.css'
import type {ProgressBarCustomProps} from './types'

export const ProgressBarSegmented = ({
  color,
  completed,
  consistentContentSizing,
  hideNumerals,
  percentCompleted,
  total,
  ...progressBarProps
}: ProgressBarCustomProps) => {
  const {accent} = useNamedColor(color)
  const segmentsCount = Math.min(total, 22)
  const segmentsProgress = Math.floor((segmentsCount * percentCompleted) / 100)
  const segmentsProgressOrMinProgress = Math.max(segmentsProgress, 1)
  const segmentsCompleteAdjusted = total <= segmentsCount ? completed : segmentsProgressOrMinProgress
  const segmentsComplete = percentCompleted === 0 ? 0 : segmentsCompleteAdjusted
  const segmentsIncomplete = segmentsCount - segmentsComplete

  const containerClasses = clsx(styles.containerSegmented, {
    [`${styles.consistentContentSizing}`]: consistentContentSizing,
  })

  return (
    <div className={containerClasses} {...testIdProps('progress-bar-segmented')}>
      {!hideNumerals && (
        <span className={styles.textCount}>
          {completed} / {total}
        </span>
      )}

      <ProgressBar className={styles.segmented} inline {...progressBarProps}>
        {new Array(segmentsComplete).fill(null).map((_, i) => (
          // Adding aria-hidden since the percent span conveys the information
          // eslint-disable-next-line @eslint-react/no-array-index-key
          <ProgressBar.Item aria-hidden key={i} className={styles.barItemComplete} sx={{backgroundColor: accent}} />
        ))}
        {new Array(segmentsIncomplete).fill(null).map((_, i) => (
          <ProgressBar.Item
            // Adding aria-hidden since the percent span conveys the information
            aria-hidden
            // eslint-disable-next-line @eslint-react/no-array-index-key
            key={i}
            className={styles.barItemIncomplete}
            sx={{backgroundColor: accent}}
          />
        ))}
      </ProgressBar>

      {!hideNumerals && <span className={styles.textPercentage}>{percentCompleted}%</span>}
    </div>
  )
}

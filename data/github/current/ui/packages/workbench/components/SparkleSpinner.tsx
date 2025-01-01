import {clsx} from 'clsx'
import {memo} from 'react'

import styles from './SparkleSpinner.module.css'

interface SparkleSpinnerProps {
  size?: 'small' | 'medium' | 'large'
}

export function UnmemoizedSparkleSpinner(props: SparkleSpinnerProps) {
  const {size = 'medium'} = props

  return (
    <svg
      aria-hidden="true"
      focusable={false}
      className={clsx(styles.sparkleSpinner, {
        [styles.medium]: size === 'medium',
        [styles.small]: size === 'small',
        [styles.large]: size === 'large',
      })}
    >
      <use xlinkHref="/images/modules/spark/sparkles.svg#sparkle-spinner" />
    </svg>
  )
}

export const SparkleSpinner = memo(UnmemoizedSparkleSpinner)

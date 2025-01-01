import {testIdProps} from '@github-ui/test-id-props'
import {CounterLabel} from '@primer/react'

import styles from './filter-counter-label.module.css'

type FilterCounterLabelProps = {
  /**
   * The number of results that match the filter and should be shown in the label.
   * If null or undefined, the label will not be shown.
   */
  filterCount: number | null | undefined

  /**
   * Whether or not to explicitly hide the counter label (even if there are filtered results)
   */
  hideCounterLabel: boolean
}

export function FilterCounterLabel({filterCount, hideCounterLabel}: FilterCounterLabelProps) {
  return !hideCounterLabel && typeof filterCount === 'number' ? (
    <div aria-live="polite" aria-atomic className={styles.Box}>
      <CounterLabel {...testIdProps('filter-results-count')}>{filterCount}</CounterLabel>
      <span className="sr-only"> {filterCount === 1 ? 'matching item' : 'matching items'}</span>
    </div>
  ) : null
}

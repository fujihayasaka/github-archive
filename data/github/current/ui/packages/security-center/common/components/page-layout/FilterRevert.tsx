import {FilterRevert as UiFilterRevert} from '@github-ui/filter'

import styles from './FilterRevert.module.css'

function FilterRevert({show, onRevert}: {show: boolean; onRevert: () => void}): JSX.Element | null {
  if (!show) {
    return null
  }

  return (
    <div className={styles.UIFilterRevertContainer}>
      <UiFilterRevert as="button" onClick={onRevert} />
    </div>
  )
}

FilterRevert.displayName = 'PageLayout.FilterRevert'

export default FilterRevert

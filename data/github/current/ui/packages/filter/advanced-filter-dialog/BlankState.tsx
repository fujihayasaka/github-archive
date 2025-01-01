import {testIdProps} from '@github-ui/test-id-props'

import type {FilterProvider} from '../types'
import {AddFilterButton} from './AddFilterButton'
import styles from './BlankState.module.css'

interface BlankStateProps {
  isNarrowBreakpoint: boolean
  addFilterButtonMobileRef: React.RefObject<HTMLButtonElement>
  filterProviders: FilterProvider[]
  addNewFilterBlock: (provider: FilterProvider) => void
}

export const BlankState = ({
  isNarrowBreakpoint,
  addFilterButtonMobileRef,
  filterProviders,
  addNewFilterBlock,
}: BlankStateProps) => {
  return (
    <div className={styles.Box_0} {...testIdProps('afd-no-content')}>
      <div className={styles.Box_1}>Build complex filter queries</div>
      <div className={styles.Box_2}>To start building your query add your first filter using the button below.</div>
      <div className={styles.Box_3}>
        <AddFilterButton
          size={isNarrowBreakpoint ? 'medium' : 'small'}
          ref={addFilterButtonMobileRef}
          filterProviders={filterProviders}
          addNewFilterBlock={addNewFilterBlock}
        />
      </div>
    </div>
  )
}

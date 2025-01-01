import type {FilterProvider, MutableFilterBlock} from '../types'
import {AddFilterButton} from './AddFilterButton'
import {AdvancedFilterItem} from './AdvancedFilterItem'
import styles from './FilterList.module.css'

interface FilterListProps {
  filterBlocks: MutableFilterBlock[]
  filterProviders: FilterProvider[]
  updateFilterBlock: (filterBlock: MutableFilterBlock) => void
  deleteFilterBlock: (index: number) => void
  isNarrowBreakpoint: boolean
  addFilterButtonMobileLastRowRef: React.RefObject<HTMLButtonElement>
  addNewFilterBlock: (provider: FilterProvider) => void
}

export const FilterList = ({
  filterBlocks,
  filterProviders,
  updateFilterBlock,
  deleteFilterBlock,
  isNarrowBreakpoint,
  addFilterButtonMobileLastRowRef,
  addNewFilterBlock,
}: FilterListProps) => {
  return (
    <div className={styles.Box_0}>
      <div className={styles.Box_1}>
        <div className={styles.Box_2} />
        <div className={styles.Box_3} />
        <span className={styles.Box_3}>Qualifier</span>
        <span className={styles.Text_0}>Operator</span>
        <span className={styles.Box_3}>Value</span>
        <div />
      </div>
      {filterBlocks.map((filterBlock, index) => (
        <AdvancedFilterItem
          // eslint-disable-next-line @eslint-react/no-array-index-key
          key={`advanced-filter-item-${index}`}
          filterBlock={filterBlock}
          filterProviders={filterProviders}
          updateFilterBlock={updateFilterBlock}
          index={index}
          deleteFilterBlock={deleteFilterBlock}
        />
      ))}
      <div className={styles.Box_4}>
        <AddFilterButton
          size={isNarrowBreakpoint ? 'medium' : 'small'}
          ref={addFilterButtonMobileLastRowRef}
          filterProviders={filterProviders}
          addNewFilterBlock={addNewFilterBlock}
        />
      </div>
    </div>
  )
}

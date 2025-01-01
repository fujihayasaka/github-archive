import {Stack} from '@primer/react'
import type {PropsWithChildren, ReactElement} from 'react'

import type DatePicker from './DatePicker'
import type Filter from './Filter'
import styles from './FilterBar.module.css'
import type FilterRevert from './FilterRevert'

interface Props {
  filter: ReactElement<typeof Filter>
  datePicker?: ReactElement<typeof DatePicker>
  revert: ReactElement<typeof FilterRevert>
}

function FilterBar(props: PropsWithChildren<Props>): JSX.Element {
  return (
    <div className={styles.FilterBarContainer}>
      <Stack direction="horizontal" wrap="wrap" justify="space-between">
        {props.filter}
        {props.children}
        {props.datePicker}
      </Stack>
      {props.revert}
    </div>
  )
}

FilterBar.displayName = 'PageLayout.FilterBar'

export default FilterBar

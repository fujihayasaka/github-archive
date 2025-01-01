import {useMemo, useState} from 'react'

import {Filter, FilterRevert} from '../../Filter'
import {StateFilterProvider} from '../../providers'
import styles from './ExternalWrapper.module.css'

export const ExternalWrapper = () => {
  const startingValue = ''
  const [filterValue, setFilterValue] = useState(startingValue)
  const providers = useMemo(() => [new StateFilterProvider('mixed')], [])

  return (
    <>
      <Filter
        id="test-filter"
        context={{repo: 'github/github'}}
        label="Filter items"
        filterValue={filterValue}
        providers={providers}
        onChange={(value: string) => {
          setFilterValue(value)
        }}
      />
      <FilterRevert
        href="#"
        onClick={e => {
          setFilterValue(startingValue)
          e.preventDefault()
        }}
        className={styles.FilterRevert_0}
      />
    </>
  )
}

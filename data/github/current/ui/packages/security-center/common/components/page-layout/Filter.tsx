import {Filter as UiFilter, type FilterProvider} from '@github-ui/filter'
import {useEffect, useState} from 'react'

import styles from './Filter.module.css'

export type FilterProps = {
  providers: FilterProvider[]
  query: string
  onSubmit: (query: string) => void
  onValidation?: (messages: string[]) => void
}

function Filter({providers, query, onSubmit, onValidation}: FilterProps): JSX.Element {
  // state of the filter input control, before it is submitted
  const [filterValue, setFilterValue] = useState(query)

  // if the prop changes externally, update our state (e.g. on filter revert)
  useEffect(() => {
    setFilterValue(query)
  }, [query])

  return (
    <UiFilter
      id="security-overview-page-filter"
      label="Filter"
      placeholder="Filter"
      providers={providers}
      filterValue={filterValue}
      onChange={setFilterValue}
      onSubmit={request => onSubmit(request.raw)}
      className={styles.UiFilter_0}
      showValidationMessage={onValidation == null}
      onValidation={onValidation}
    />
  )
}

Filter.displayName = 'PageLayout.Filter'

export default Filter

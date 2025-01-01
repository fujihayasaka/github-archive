import {Filter, type AdvancedFilterDialogRef, type FilterProvider} from '@github-ui/filter'
import {useSyncedState} from '@github-ui/use-synced-state'

import styles from './OrgAlertsFilter.module.css'

export type OrgAlertsFilterPayload = {
  providers: FilterProvider[]
  query: string
  setQuery: (query: string) => void
  advancedFilterDialogRef?: React.RefObject<AdvancedFilterDialogRef>
}

export const OrgAlertsFilter = ({providers, query, setQuery, advancedFilterDialogRef}: OrgAlertsFilterPayload) => {
  const [filterValue, setFilterValue] = useSyncedState(query)

  return (
    <div className={styles.Box_0}>
      <Filter
        id="security-campaign-org-alerts-filter"
        label="Filter"
        placeholder="Filter"
        providers={providers}
        filterValue={filterValue}
        onChange={setFilterValue}
        onSubmit={request => setQuery(request.raw)}
        className={styles.Filter_0}
        advancedFilterDialogRef={advancedFilterDialogRef}
      />
    </div>
  )
}

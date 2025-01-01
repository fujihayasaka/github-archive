import DataCard from '@github-ui/data-card'
import {LoadingSkeleton} from '@github-ui/skeleton/LoadingSkeleton'

export function ProgressMetricLoading() {
  return (
    <DataCard cardTitle="Campaign progress">
      <div className="d-flex color-fg-muted mb-2">
        <LoadingSkeleton variant="rounded" height="md" width="30%" />
        <LoadingSkeleton variant="rounded" height="md" width="20%" className="ml-auto" />
      </div>
      <LoadingSkeleton variant="rounded" height="12px" width="100%" className="mb-1" />
    </DataCard>
  )
}

import {DiffStats} from '@github-ui/diffs/DiffStats'
import {useDiffstatData} from '../page-data/loaders/use-diffstat-data'

export function DiffStat() {
  const {
    data: {diffstat},
  } = useDiffstatData()

  return (
    <DiffStats
      linesAdded={diffstat.linesAdded}
      linesDeleted={diffstat.linesDeleted}
      linesChanged={diffstat.linesChanged}
      tooltipDirection="nw"
    />
  )
}

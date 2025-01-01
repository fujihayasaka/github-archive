import {IssuesLoadingSkeleton} from '@github-ui/issues-loading-skeleton'
import {ActionList} from '@primer/react'

import {VALUES} from '../../../constants/values'

type SelectTeamsQueryLoadingProps = {
  nrRows?: number
}

export function SelectTeamsQueryLoading({nrRows = VALUES.selectedTeamsLoadingSize}: SelectTeamsQueryLoadingProps) {
  const rows = Array(nrRows)
    .fill(0)
    .map((_, i) => (
      // eslint-disable-next-line @eslint-react/no-array-index-key
      <ActionList.Item key={i} selected={false}>
        <ActionList.LeadingVisual>
          <IssuesLoadingSkeleton height="lg" width="lg" />
        </ActionList.LeadingVisual>
        <IssuesLoadingSkeleton height="md" width="random" />
      </ActionList.Item>
    ))
  return <ActionList selectionVariant="multiple">{rows}</ActionList>
}

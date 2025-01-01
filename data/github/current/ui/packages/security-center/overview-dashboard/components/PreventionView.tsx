import type {RangeSelection} from '@github-ui/date-picker'
import {Stack} from '@primer/react/experimental'

import {isRangeSelection} from '../../common/components/date-span-picker'
import type {CustomProperty} from '../../common/filter-providers/types'
import type {Period} from '../../common/utils/date-period'
import AlertsFixedInPullRequestsCard from './alerts-fixed-card/AlertsFixedInPullRequestsCard'
import {PreventedAndIntroducedChart} from './prevented-and-introduced-chart/PreventedAndIntroducedChart'
import PullRequestAlertsFixedWithAutofixCard from './pull-request-alerts-fixed-with-autofix-card/PullRequestAlertsFixedWithAutofixCard'

export interface PreventionViewProps {
  submittedQuery: string
  startDateString: string
  endDateString: string
  selectedDateSpan: Period | RangeSelection
  customProperties: CustomProperty[]
  allowAutofixFeatures?: boolean
}

export function PreventionView({
  submittedQuery,
  startDateString,
  endDateString,
  customProperties,
  selectedDateSpan,
  allowAutofixFeatures,
}: PreventionViewProps): JSX.Element {
  return (
    <Stack>
      <PreventedAndIntroducedChart query={submittedQuery} startDate={startDateString} endDate={endDateString} />

      <Stack direction="horizontal">
        <AlertsFixedInPullRequestsCard
          query={submittedQuery}
          customProperties={customProperties}
          startDate={startDateString}
          endDate={endDateString}
          datePeriod={isRangeSelection(selectedDateSpan) ? undefined : selectedDateSpan}
        />

        {allowAutofixFeatures && (
          <PullRequestAlertsFixedWithAutofixCard
            query={submittedQuery}
            startDate={startDateString}
            endDate={endDateString}
          />
        )}
      </Stack>
    </Stack>
  )
}

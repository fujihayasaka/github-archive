import {Stack} from '@primer/react/experimental'
import {useMemo} from 'react'

import {AlertActivityChart} from './alert-activity-chart/AlertActivityChart'
import {AlertTrendsChart} from './alert-trends-chart/AlertTrendsChart'
import type {GroupingType} from './alert-trends-chart/grouping-type'
import {HistoricalAlertsFixedWithAutofixCard} from './historical-alerts-fixed-with-autofix-card/HistoricalAlertsFixedWithAutofixCard'
import {MeanTimeToRemediateCard} from './mean-time-to-remediate-card/MeanTimeToRemediateCard'
import {NetResolveRateCard} from './net-resolve-rate-card/NetResolveRateCard'

export interface RemediationViewProps {
  submittedQuery: string
  startDateString: string
  endDateString: string
  alertTrendsGrouping?: GroupingType
  allowAutofixFeatures?: boolean
}

export function RemediationView({
  submittedQuery,
  startDateString,
  endDateString,
  alertTrendsGrouping,
  allowAutofixFeatures,
}: RemediationViewProps): JSX.Element {
  const cardProps = useMemo(() => {
    return {
      query: submittedQuery,
      startDate: startDateString,
      endDate: endDateString,
    }
  }, [submittedQuery, startDateString, endDateString])

  return (
    <Stack direction="vertical">
      <AlertTrendsChart
        isOpenSelected={false}
        query={submittedQuery}
        startDate={startDateString}
        endDate={endDateString}
        grouping={alertTrendsGrouping}
      />

      <Stack direction="horizontal">
        <MeanTimeToRemediateCard {...cardProps} />
        <NetResolveRateCard {...cardProps} />
        {allowAutofixFeatures && <HistoricalAlertsFixedWithAutofixCard {...cardProps} />}
      </Stack>

      <AlertActivityChart {...cardProps} />
    </Stack>
  )
}

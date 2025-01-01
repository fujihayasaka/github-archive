import {Observer} from '../observables/Observer'
import {LABELS} from '../resources/labels'
import type {IMetricsService} from '../services/metrics-service'
import type {MetricsView} from '../models/models'
import {LoadingSkeleton} from '@github-ui/skeleton/LoadingSkeleton'
import {DateRangeType} from '../models/enums'
import type {ReactNode} from 'react'
import {RelativeTime} from '@primer/react'
import {Utils} from '../utils/utils'

export interface MetricsDateRangeDescriptionProps {
  metricsService: IMetricsService
}

export const MetricsDateRangeDescription = (props: MetricsDateRangeDescriptionProps) => {
  const metricsService = props.metricsService
  return (
    <Observer loading={metricsService.getLoading()} view={metricsService.getMetricsView()}>
      {(obs: {loading: boolean; view: MetricsView}) => {
        if (obs.loading) {
          return <LoadingSkeleton height={'21px'} width={'300px'} />
        }

        const start = Utils.getUTCDateString(obs.view.startTime)
        let end: ReactNode = <RelativeTime date={obs.view.endTime} />

        if (showActualDate(obs.view)) {
          end = Utils.getUTCDateString(obs.view.endTime)
        }

        return (
          <span>
            {`${LABELS.dateDescription} ${start} ${LABELS.dateDescriptionDelimiter} `}
            {end}
          </span>
        )
      }}
    </Observer>
  )
}

const showActualDate = (view: MetricsView) => {
  if (view.dateRangeType === DateRangeType.LastMonth) {
    return true
  }

  if (view.dateRangeType === DateRangeType.Custom) {
    const time = view.endTime.getUTCHours() + view.endTime.getUTCMinutes()

    if (time === 0) {
      // if this is the exact start of a day then display as date because this means it is not showing delay
      return true
    }
  }

  return false
}

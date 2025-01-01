import DataCard from '@github-ui/data-card'
import {Octicon} from '@primer/react/deprecated'
import {number as formatNumber} from '@github-ui/formatters'
import pluralize from 'pluralize'
import {ProgressMetricLoading} from './ProgressMetricLoading'
import {calculateDaysLeft} from '../utils/calculate-days-left'
import {DotFillIcon} from '@primer/octicons-react'

export interface ProgressMetricProps {
  openCount: number | undefined
  closedCount: number | undefined
  openWithLinksCount: number | undefined
  isSuccess: boolean
  endsAt: Date
  createdAt: Date
  isClosed?: boolean
  action?: React.ReactNode
}

const percentFormatter = new Intl.NumberFormat('en-US', {style: 'percent'})

export function ProgressMetric({
  openCount = 0,
  closedCount = 0,
  openWithLinksCount = 0,
  isSuccess,
  endsAt,
  createdAt,
  isClosed,
  action,
}: ProgressMetricProps) {
  const totalCount = openCount + closedCount
  const fractionAlertsClosed = totalCount === 0 ? 0 : closedCount / totalCount
  const fractionAlertsWithLinks = totalCount === 0 ? 0 : openWithLinksCount / totalCount

  const formattedPercentAlertsClosed = percentFormatter.format(fractionAlertsClosed)

  const daysLeft = calculateDaysLeft(endsAt)
  const isCreatedToday = createdAt.toDateString() === new Date().toDateString()
  const isCompleted = fractionAlertsClosed === 1
  const isOverdue = daysLeft < 0

  const progressText = () => {
    if (isClosed) {
      return 'Campaign closed but progress may change if alerts close or reopen'
    }
    if (isCompleted) {
      return 'Campaign has been completed'
    }
    if (isOverdue) {
      return `Campaign overdue by ${Math.abs(daysLeft)} ${pluralize('day', Math.abs(daysLeft))}`
    }
    if (!isCreatedToday) {
      return `Campaign started ${Math.abs(calculateDaysLeft(createdAt))} ${pluralize(
        'day',
        Math.abs(calculateDaysLeft(createdAt)),
      )} ago`
    }
    return 'Campaign started today'
  }

  if (!isSuccess) {
    return <ProgressMetricLoading />
  }

  const progressBarData = []
  if (fractionAlertsClosed > 0) {
    progressBarData.push({
      progress: fractionAlertsClosed * 100,
      color: 'done.emphasis',
      label: 'Closed',
    })
  }
  if (fractionAlertsWithLinks > 0) {
    progressBarData.push({
      progress: fractionAlertsWithLinks * 100,
      color: 'neutral.emphasis',
      label: 'In progress',
    })
  }

  return (
    <DataCard cardTitle="Campaign progress">
      <div className="mt-n2">{action}</div>
      <div className="d-flex color-fg-muted mt-1">
        <p className="d-flex flex-auto mb-0">
          {formattedPercentAlertsClosed} ({formatNumber(closedCount)} {pluralize('alert', closedCount)})
        </p>
        <span>
          {formatNumber(openCount)} {pluralize('alert', openCount)} left
        </span>
      </div>
      <DataCard.ProgressBar
        data={progressBarData}
        aria-label={`Progress: ${formattedPercentAlertsClosed} of ${pluralize('alert', closedCount)} closed`}
      />
      <DataCard.Description>
        {openWithLinksCount > 0 && (
          <span className="d-flex flex-wrap gap-2 pb-2">
            <span className="d-flex">
              {/* Without !important, Octicon overwrites vertical-align to text-bottom */}
              <Octicon icon={DotFillIcon} sx={{color: 'done.emphasis', verticalAlign: 'sub !important'}} />{' '}
              {formatNumber(closedCount)} closed
            </span>
            <span className="d-flex">
              <Octicon icon={DotFillIcon} sx={{color: 'neutral.emphasis', verticalAlign: 'sub !important'}} />{' '}
              {formatNumber(openWithLinksCount)} in progress
            </span>
          </span>
        )}
        {progressText()}
      </DataCard.Description>
    </DataCard>
  )
}

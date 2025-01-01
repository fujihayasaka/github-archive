import DataCard from '@github-ui/data-card'
import {Box, Text} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
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
    <DataCard cardTitle="Campaign progress" action={action}>
      <Box sx={{display: 'flex', color: 'fg.muted'}}>
        <Text sx={{flexGrow: 1}}>
          {formattedPercentAlertsClosed} ({closedCount} {pluralize('alert', closedCount)})
        </Text>
        <span>
          {openCount} {pluralize('alert', openCount)} left
        </span>
      </Box>
      <DataCard.ProgressBar
        data={progressBarData}
        aria-label={`Progress: ${formattedPercentAlertsClosed} of ${pluralize('alert', closedCount)} closed`}
      />
      <DataCard.Description>
        {openWithLinksCount > 0 && (
          <Box sx={{display: 'flex', mb: 2}} as="span">
            <Text sx={{fontWeight: 'bold', mr: 2}}>
              {/* Without !important, Octicon overwrites vertical-align to text-bottom */}
              <Octicon icon={DotFillIcon} sx={{color: 'done.emphasis', verticalAlign: 'sub !important'}} />{' '}
              {closedCount} closed
            </Text>
            <Text sx={{fontWeight: 'bold'}}>
              <Octicon icon={DotFillIcon} sx={{color: 'neutral.emphasis', verticalAlign: 'sub !important'}} />{' '}
              {openWithLinksCount} in progress
            </Text>
          </Box>
        )}
        <span>{progressText()}</span>
      </DataCard.Description>
    </DataCard>
  )
}

import DataCard from '@github-ui/data-card'
import {Box, RelativeTime} from '@primer/react'
import pluralize from 'pluralize'
import {calculateDaysLeft} from '../utils/calculate-days-left'
import {useMemo} from 'react'

export interface StatusMetricProps {
  endsAt: Date
  isCompleted: boolean
  closedAt?: Date
}

export function StatusMetric({endsAt, isCompleted, closedAt}: StatusMetricProps) {
  const daysLeft = calculateDaysLeft(endsAt)
  const isOverdue = daysLeft < 0

  const descriptionText = () => {
    if (isCompleted && isOverdue) {
      return 'Campaign ended on'
    }
    if (isOverdue) {
      return 'Due date was'
    }
    return 'Due date is'
  }

  const campaignStatus = useMemo(() => {
    if (closedAt) {
      return 'closed' as const
    }

    if (isCompleted) {
      return 'completed' as const
    }

    if (isOverdue) {
      return 'overdue' as const
    }

    return 'open' as const
  }, [closedAt, isCompleted, isOverdue])

  return (
    <DataCard cardTitle="Status">
      <div>
        {campaignStatus === 'closed' && <Box sx={{fontSize: '24px', fontWeight: 400, lineHeight: '24px'}}>Closed</Box>}
        {campaignStatus === 'open' && (
          <DataCard.Counter count={Math.abs(daysLeft)} metric={`${pluralize('day', Math.abs(daysLeft))} left`} />
        )}
        {campaignStatus === 'overdue' && (
          <Box sx={{fontSize: '24px', fontWeight: 400, lineHeight: '24px'}}>Overdue</Box>
        )}
        {campaignStatus === 'completed' && (
          <Box sx={{fontSize: '24px', fontWeight: 400, lineHeight: '24px'}}>Completed</Box>
        )}
      </div>
      <DataCard.Description>
        {closedAt && (
          <>
            Campaign closed on{' '}
            {closedAt.toLocaleDateString('default', {month: 'short', day: 'numeric', year: 'numeric'})}. Due date was{' '}
            {endsAt.toLocaleDateString('default', {month: 'short', day: 'numeric', year: 'numeric'})}.
          </>
        )}
        {!closedAt && (
          <>
            {descriptionText()} <RelativeTime date={endsAt} format="datetime" />
          </>
        )}
      </DataCard.Description>
    </DataCard>
  )
}

import DataCard from '@github-ui/data-card'
import {RelativeTime} from '@primer/react'
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
        {campaignStatus === 'closed' && <div className="f2 text-normal">Closed</div>}
        {campaignStatus === 'open' && (
          <div className="d-flex flex-items-baseline">
            <DataCard.Counter count={Math.abs(daysLeft)} />
            <span className="f4 fgColor-muted ml-1">{`${pluralize('day', Math.abs(daysLeft))} left`}</span>
          </div>
        )}
        {campaignStatus === 'overdue' && <div className="f2 text-normal">Overdue</div>}
        {campaignStatus === 'completed' && <div className="f2 text-normal">Completed</div>}
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

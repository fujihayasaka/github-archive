import {useMemo} from 'react'
import {LABELS} from './constants/labels'
import styles from './RepositoryMilestone.module.css'
import {AlertFillIcon} from '@primer/octicons-react'
import {useFragment} from 'react-relay'
import {graphql} from 'relay-runtime'
import type {MilestoneDate$key} from './__generated__/MilestoneDate.graphql'

type MilestoneDateProps = {
  milestone: MilestoneDate$key
}

export function MilestoneDate({milestone}: MilestoneDateProps) {
  const currentMilestone = useFragment(
    graphql`
      fragment MilestoneDate on Milestone {
        dueOn
      }
    `,
    milestone,
  )

  const totalOverDue = useMemo(() => {
    if (!currentMilestone || !currentMilestone.dueOn) return null
    const dueOn = new Date(currentMilestone.dueOn)
    const today = new Date()

    if (dueOn > today) return null

    // Set both dates to midnight to avoid partial day errors
    today.setHours(0, 0, 0, 0)
    dueOn.setHours(0, 0, 0, 0)

    const diffTime = today.getTime() - dueOn.getTime()

    const diffDays = Math.floor(diffTime / (1000 * 60 * 60 * 24))

    if (diffDays < 30) {
      return `${diffDays} day(s)`
    }

    const diffMonths = Math.floor(diffDays / 30)
    if (diffMonths < 12) {
      return `${diffMonths} month(s)`
    }

    const diffYears = Math.floor(diffMonths / 12)
    return `${diffYears} year(s)`
  }, [currentMilestone])

  const formattedDate = useMemo(() => {
    if (!currentMilestone.dueOn) return null

    const dueDate = new Date(currentMilestone.dueOn)

    return dueDate.toLocaleDateString('en-US', {
      month: 'long',
      day: 'numeric',
      year: 'numeric',
      timeZone: 'UTC',
    })
  }, [currentMilestone.dueOn])

  return (
    <>
      {totalOverDue ? (
        <div className={styles.milestoneData}>
          <div className={styles.overDue}>
            <AlertFillIcon size={12} />
            <span>
              {LABELS.milestoneOverdue} {totalOverDue}
            </span>
          </div>
          <span className={styles.middot}>{LABELS.separator}</span>
        </div>
      ) : null}
      <div className={styles.milestoneData}>
        {currentMilestone.dueOn ? (
          <span>
            {LABELS.dueBy} {formattedDate}
          </span>
        ) : (
          <span>{LABELS.noDueDate}</span>
        )}
      </div>
    </>
  )
}

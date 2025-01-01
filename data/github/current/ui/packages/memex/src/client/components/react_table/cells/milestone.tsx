import {memo} from 'react'

import type {Milestone as IMilestone} from '../../../api/common-contracts'
import {LinkCell} from './link-cell'
import styles from './milestone.module.css'

interface MilestoneProps {
  milestone: IMilestone | undefined
  isDisabled?: boolean
}

export const Milestone: React.FC<MilestoneProps> = memo(function Milestone({milestone, isDisabled}) {
  return (
    <div className={styles.Box}>
      {milestone && (
        <LinkCell href={milestone.url} muted isDisabled={isDisabled}>
          {milestone.title}
        </LinkCell>
      )}
    </div>
  )
})

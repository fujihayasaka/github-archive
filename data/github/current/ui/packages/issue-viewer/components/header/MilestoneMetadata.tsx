import type {MilestonePickerMilestone$data} from '@github-ui/item-picker/MilestonePickerMilestone.graphql'
import {MilestoneIcon} from '@primer/octicons-react'
import {Link, Truncate} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import styles from './MilestoneMetadata.module.css'

export const MilestoneMetadata = ({milestone}: {milestone: MilestonePickerMilestone$data}) => {
  return (
    <Link href={milestone.url} aria-label={milestone.title} muted className={styles.milestoneLink}>
      <Octicon icon={MilestoneIcon} size={16} />
      &nbsp;
      <Truncate title={milestone.title} className={styles.milestoneTitle} sx={{verticalAlign: 'bottom'}}>
        {milestone.title}
      </Truncate>
    </Link>
  )
}

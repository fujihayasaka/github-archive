import {useCurrentUser} from '@github-ui/current-user'
import {Label} from '@primer/react'

import styles from './FeedbackLink.module.css'

const STAFF_FEEDBACK_LINK = 'https://gh.io/copilot-workspace-feedback-staff'
const USER_FEEDBACK_LINK = 'https://gh.io/copilot-workspace-feedback'

export function FeedbackLink() {
  const currentUser = useCurrentUser()

  return (
    <a
      target="_blank"
      rel="noopener noreferrer"
      href={currentUser?.isStaff ? STAFF_FEEDBACK_LINK : USER_FEEDBACK_LINK}
      className={styles.link}
    >
      <Label className={styles.label}>
        <span className={styles.labelPreview}>Preview</span>
        <span className={styles.labelFeedback}>Give feedback</span>
      </Label>
    </a>
  )
}

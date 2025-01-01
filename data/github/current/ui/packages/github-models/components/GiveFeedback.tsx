import {testIdProps} from '@github-ui/test-id-props'
import {Label, Link} from '@primer/react'
import {BetaLabel} from '@github-ui/lifecycle-labels/beta'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import styles from './GiveFeedback.module.css'
import {feedbackUrl} from '../constants'

export function GiveFeedback({playground, mobile}: {playground?: boolean; mobile?: boolean}) {
  const lifecycleLabelNameEnabled = isFeatureEnabled('lifecycle_label_name_updates')

  if (mobile) {
    return (
      <div className={styles.giveFeedbackContainerMobile}>
        <div className={styles.thoughtsTextMobile}>Thoughts on GitHub Models?</div>
        <div className={styles.lifeCycleLabelMobile}>
          {lifecycleLabelNameEnabled ? <BetaLabel /> : <Label variant="success">Beta</Label>}
          {!playground && (
            <Link href={feedbackUrl} tabIndex={0}>
              Give feedback
            </Link>
          )}
        </div>
      </div>
    )
  }
  return (
    <div className={styles.lifeCycleLabel}>
      {lifecycleLabelNameEnabled ? <BetaLabel /> : <Label variant="success">Beta</Label>}
      {!playground && (
        <Link {...testIdProps('feedback-link')} href={feedbackUrl} className={styles.giveFeedbackLink} tabIndex={0}>
          Give feedback
        </Link>
      )}
    </div>
  )
}

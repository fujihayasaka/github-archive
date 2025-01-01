import {testIdProps} from '@github-ui/test-id-props'
import {Label, Link} from '@primer/react'
import {BetaLabel} from '@github-ui/lifecycle-labels/beta'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import styles from './GiveFeedback.module.css'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {GiveFeedbackPopover} from './GiveFeedbackPopover'
import {feedbackUrl} from '../constants'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {ShowModelPayload} from '../types'
import {useCallback, useState} from 'react'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {dismissUserNoticePath} from '@github-ui/paths'

export function GiveFeedback({playground, mobile}: {playground?: boolean; mobile?: boolean}) {
  const lifecycleLabelNameEnabled = isFeatureEnabled('lifecycle_label_name_updates')
  const feedbackBannerEnabled = useFeatureFlag('github_models_feedback_banner')
  const showLink = feedbackBannerEnabled || !playground
  const {playgroundFeedbackPopoverDismissed} = useRoutePayload<ShowModelPayload>()
  const showPopOverOnLand = !feedbackBannerEnabled && !playgroundFeedbackPopoverDismissed
  const [isOpen, setIsOpen] = useState(showPopOverOnLand)

  const handleClose = useCallback(() => {
    if (showPopOverOnLand) {
      verifiedFetch(dismissUserNoticePath({noticeName: 'github_models_playground_feedback_popover'}), {method: 'POST'})
    }
    setIsOpen(false)
  }, [showPopOverOnLand])

  if (mobile) {
    return (
      <div className={styles.giveFeedbackContainerMobile}>
        <div className={styles.thoughtsTextMobile}>Thoughts on GitHub Models?</div>
        <div className={styles.lifeCycleLabelMobile}>
          {lifecycleLabelNameEnabled ? <BetaLabel /> : <Label variant="success">Beta</Label>}
          {showLink ? (
            <Link href={feedbackUrl} tabIndex={0}>
              Give feedback
            </Link>
          ) : (
            <div className="position-relative">
              <Link as="button" onClick={() => setIsOpen(true)}>
                Give feedback
              </Link>
              <div>{isOpen && <GiveFeedbackPopover handleClose={handleClose} mobile />}</div>
            </div>
          )}
        </div>
      </div>
    )
  }
  return (
    <div className={styles.lifeCycleLabel}>
      {lifecycleLabelNameEnabled ? <BetaLabel /> : <Label variant="success">Beta</Label>}

      {showLink ? (
        <Link {...testIdProps('feedback-link')} href={feedbackUrl} className={styles.giveFeedbackLink} tabIndex={0}>
          Give feedback
        </Link>
      ) : (
        <div className="position-relative">
          <Link as="button" onClick={() => setIsOpen(true)} className="text-small">
            Give feedback
          </Link>
          <div>{isOpen && <GiveFeedbackPopover handleClose={handleClose} />}</div>
        </div>
      )}
    </div>
  )
}

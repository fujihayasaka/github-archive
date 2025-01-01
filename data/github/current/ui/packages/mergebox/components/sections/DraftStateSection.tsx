import {GitPullRequestDraftIcon, StopIcon} from '@primer/octicons-react'
import {useAnalytics} from '@github-ui/use-analytics'
import {CircleOcticon, Button, Flash, Spinner} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import useSafeState from '@github-ui/use-safe-state'

import {HEADER_ICON_SIZE} from '../../constants'
import type {PullRequestState} from '../../types'
import {useMarkReadyForReviewMutation} from '../../hooks/mutations/use-mark-ready-for-review-mutation'
import {MergeBoxSectionHeader} from './common/MergeBoxSectionHeader'
import {useId} from 'react'

export type DraftStateSectionProps = {
  isDraft: boolean
  state: PullRequestState
  viewerCanUpdate: boolean
}

/**
 *
 * Renders if the pull request is in a Draft State
 */
export function DraftStateSection({isDraft, state, viewerCanUpdate}: DraftStateSectionProps) {
  const [errorMessage, setErrorMessage] = useSafeState<string | null>(null)

  const {mutate: markReadyForReviewMutation, isPending} = useMarkReadyForReviewMutation({
    onError: (e: Error) => {
      setErrorMessage(e.message)
    },
  })
  const {sendAnalyticsEvent} = useAnalytics()
  const draftStateSectionAriaId = useId()

  function handleMarkReadyForReview() {
    if (isPending) return

    markReadyForReviewMutation()
    sendAnalyticsEvent(
      'draft_state_section.mark_ready_for_review',
      'MERGEBOX_DRAFT_STATE_SECTION_MARK_READY_FOR_REVIEW_BUTTON',
    )
  }

  if (state !== 'OPEN' || !isDraft || !viewerCanUpdate) {
    return null
  }

  return (
    <section
      aria-label="Draft state"
      aria-describedby={draftStateSectionAriaId}
      className="border-bottom color-border-subtle"
    >
      <MergeBoxSectionHeader
        headerId={draftStateSectionAriaId}
        title="This pull request is still a work in progress"
        subtitle="Draft pull requests cannot be merged."
        icon={
          <CircleOcticon
            size={HEADER_ICON_SIZE}
            icon={() => <GitPullRequestDraftIcon size={16} />}
            sx={{bg: 'neutral.emphasis', color: 'fg.onEmphasis'}}
          />
        }
        rightSideContent={
          <Button aria-disabled={isPending} inactive={isPending} onClick={handleMarkReadyForReview}>
            <div className="d-flex flex-row flex-items-center">
              {isPending ? (
                <>
                  <Spinner size="small" sx={{mr: 1}} />
                  <span>Marking ready for review...</span>
                </>
              ) : (
                'Ready for review'
              )}
            </div>
          </Button>
        }
      >
        {errorMessage && (
          <Flash sx={{mb: 3}} variant="danger">
            <Octicon sx={{mr: 2}} icon={StopIcon} />
            {errorMessage}
          </Flash>
        )}
      </MergeBoxSectionHeader>
    </section>
  )
}

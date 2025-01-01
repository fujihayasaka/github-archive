import {GitPullRequestDraftIcon, StopIcon} from '@primer/octicons-react'
import {useAnalytics} from '@github-ui/use-analytics'
import {CircleOcticon, Button, Flash} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import useSafeState from '@github-ui/use-safe-state'

import {HEADER_ICON_SIZE} from '../../constants'
import {useMarkReadyForReviewMutation} from '../../hooks/mutations/use-mark-ready-for-review-mutation'
import {MergeBoxSectionHeader} from './common/MergeBoxSectionHeader'
import {useId} from 'react'

/**
 *
 * Renders if the pull request is in a Draft State
 */
export function DraftStateSection({viewerCanUpdate, helpUrl}: {viewerCanUpdate: boolean; helpUrl: string}) {
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

  const url = `${helpUrl}/get-started/learning-about-github/access-permissions-on-github`

  return (
    <section
      aria-label="Draft state"
      aria-describedby={draftStateSectionAriaId}
      className="border-bottom color-border-subtle"
    >
      <MergeBoxSectionHeader
        headerId={draftStateSectionAriaId}
        title="This pull request is still a work in progress"
        subtitle={
          viewerCanUpdate ? (
            'Draft pull requests cannot be merged.'
          ) : (
            <span>
              Only those with <a href={url}>write access</a> to this repository can mark a draft pull request as ready
              for review.
            </span>
          )
        }
        icon={
          <CircleOcticon
            size={HEADER_ICON_SIZE}
            icon={() => <GitPullRequestDraftIcon size={16} />}
            sx={{bg: 'neutral.emphasis', color: 'fg.onEmphasis'}}
          />
        }
        rightSideContent={
          viewerCanUpdate ? (
            <Button
              onClick={handleMarkReadyForReview}
              loading={isPending}
              loadingAnnouncement="Marking ready for review"
            >
              Ready for review
            </Button>
          ) : undefined
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

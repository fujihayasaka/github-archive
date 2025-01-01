import type {CommentBoxConfig, CommentBoxHandle} from '@github-ui/comment-box/CommentBox'
import {
  ConversationCommentBox,
  type ConversationCommentBoxProps,
  type CommentingImplementation,
} from '@github-ui/conversations'
import useSafeState from '@github-ui/use-safe-state'
import {StopIcon, TriangleDownIcon} from '@primer/octicons-react'
import {Button, Dialog, Flash, FormControl, Heading, Radio, RadioGroup, Spinner, Stack} from '@primer/react'
import {Tooltip} from '@primer/react/deprecated'
import {Suspense, forwardRef, memo, useCallback, useEffect, useMemo, useRef} from 'react'
import {capitalize} from '@github-ui/filter/utils'

import {usePullRequestToolbarAnalytics} from '../../hooks/use-pull-request-toolbar-analytics'
import {
  PullRequestState,
  type AllowedNonCommentReviewType,
  type PullRequest,
  type Repository,
} from '../../page-data/payloads/toolbar'
import {useSubmitReviewMutation, ReviewEvent} from '../../mutations/use-submit-review-mutation'
import type {ReviewResponse} from '../../page-data/payloads/review-response'
import {useAbandonReviewMutation} from '../../mutations/use-abandon-review-mutation'
import {RelayEnvironmentProvider} from 'react-relay'
import {relayEnvironmentWithMissingFieldHandlerForNode} from '@github-ui/relay-environment'
import {usePendingReviewPageData} from '../../page-data/payloads/pending-review'
import {usePersistedReview} from '../../hooks/use-persisted-review-data'
import styles from './ReviewMenuButton.module.css'
import {useGenerateThreadPreviews} from '../../hooks/use-generate-thread-previews'
import type {FilesRoutePayload} from '../../page-data/payloads/files'
import {PendingCommentPreview} from './PendingCommentPreview'

const relayEnvironment = relayEnvironmentWithMissingFieldHandlerForNode()

export type RepositoryPermission = 'ADMIN' | 'MAINTAIN' | 'READ' | 'TRIAGE' | 'WRITE'

export interface ReviewMenuButtonProps {
  diffEntries: FilesRoutePayload['diffContents']
  commentBoxConfig: CommentBoxConfig
  commentBoxSubject: CommentingImplementation['commentBoxSubject']
  currentUserLogin: string
  pullRequest: PullRequest
  repository: Repository
  redirectOnMutation?: boolean
  tabSize?: number
}

function getApproveDisabledTooltip(
  reviewerIsAuthor: boolean,
  violatedPushPolicy: boolean,
  viewerAllowedNonCommentReviewTypes: AllowedNonCommentReviewType[],
) {
  if (reviewerIsAuthor) return "Pull request authors can't approve their own pull requests."
  if (violatedPushPolicy) return "Users that pushed changes to this pull request after it was opened can't approve"
  if (!viewerAllowedNonCommentReviewTypes.includes('APPROVE'))
    return 'Only users with explicit access to this repository may approve pull requests'
  return ''
}

function getRequestChangesDisabledTooltip(
  reviewerIsAuthor: boolean,
  viewerAllowedNonCommentReviewTypes: AllowedNonCommentReviewType[],
) {
  if (reviewerIsAuthor) return "Pull request authors can't request changes on their own pull requests."
  if (!viewerAllowedNonCommentReviewTypes.includes('REQUEST_CHANGES'))
    return 'Only users with explicit access to this repository may request changes on pull requests'
  return ''
}

function getApproveSubLabel(viewerIsCopilotAttributed: boolean) {
  if (viewerIsCopilotAttributed) {
    return 'Only users who did not collaborate with Copilot will satisfy review requirements.'
  }

  return 'Submit feedback and approve merging these changes.'
}

function getReviewMenuButtonDisplayState({
  totalPendingComments,
  viewerIsAuthor,
  viewerAllowedNonCommentReviewTypes,
  isPROpen,
}: {
  totalPendingComments?: number
  viewerIsAuthor: boolean
  viewerAllowedNonCommentReviewTypes: AllowedNonCommentReviewType[]
  isPROpen: boolean
}): {isHidden: boolean; text?: string} {
  const hasPendingComments = (totalPendingComments ?? 0) > 0
  const viewerCanApprove = viewerAllowedNonCommentReviewTypes.includes('APPROVE')
  const viewerCanRequestChanges = viewerAllowedNonCommentReviewTypes.includes('REQUEST_CHANGES')
  const isNonApprovingReviewerWithComments = !viewerCanApprove && hasPendingComments
  const isNonApprovingReviewerWithoutComments = !viewerCanApprove && !hasPendingComments

  switch (true) {
    case !isPROpen:
      return {
        isHidden: !hasPendingComments,
        text: 'comments',
      }
    case viewerIsAuthor:
    case viewerCanApprove:
    case viewerCanRequestChanges:
      return {
        isHidden: false,
        text: 'review',
      }
    case isNonApprovingReviewerWithComments:
      return {
        isHidden: false,
        text: 'comments',
      }
    case isNonApprovingReviewerWithoutComments:
    default:
      return {isHidden: true}
  }
}

const ReviewRadioButtons = memo(function ReviewRadioButtons({
  onReviewEventChange,
  reviewEvent,
  viewerAllowedNonCommentReviewTypes,
  viewerCanWriteToRepo,
  viewerHasViolatedPushPolicy,
  viewerIsAuthor,
  viewerIsCopilotAttributed,
}: {
  onReviewEventChange: (selected: string | null) => void
  reviewEvent: ReviewEvent
  viewerAllowedNonCommentReviewTypes: AllowedNonCommentReviewType[]
  viewerCanWriteToRepo: boolean
  viewerHasViolatedPushPolicy: boolean | null | undefined
  viewerIsAuthor: boolean
  viewerIsCopilotAttributed: boolean
}) {
  return (
    <RadioGroup name="reviewEvent" onChange={onReviewEventChange} className={styles.RadioGroup}>
      <RadioGroup.Label visuallyHidden>Review Event</RadioGroup.Label>
      <RadioButton
        checked={reviewEvent === ReviewEvent.comment}
        label={capitalize(ReviewEvent.comment)}
        subLabel="Submit general feedback without explicit approval."
        value={ReviewEvent.comment}
      />
      <RadioButton
        checked={reviewEvent === ReviewEvent.approve}
        disabled={!viewerAllowedNonCommentReviewTypes.includes('APPROVE')}
        label={capitalize(ReviewEvent.approve)}
        subLabel={getApproveSubLabel(viewerIsCopilotAttributed)}
        value={ReviewEvent.approve}
        disabledTooltip={getApproveDisabledTooltip(
          viewerIsAuthor,
          !!viewerHasViolatedPushPolicy,
          viewerAllowedNonCommentReviewTypes,
        )}
      />
      <RadioButton
        checked={reviewEvent === ReviewEvent.requestChanges}
        disabled={!viewerAllowedNonCommentReviewTypes.includes('REQUEST_CHANGES')}
        disabledTooltip={getRequestChangesDisabledTooltip(viewerIsAuthor, viewerAllowedNonCommentReviewTypes)}
        label={capitalize(ReviewEvent.requestChanges)}
        value={ReviewEvent.requestChanges}
        subLabel={
          viewerCanWriteToRepo
            ? 'Submit feedback that must be addressed before merging.'
            : 'Submit feedback suggesting changes.'
        }
      />
    </RadioGroup>
  )
})

function RadioButton({
  checked,
  disabled,
  disabledTooltip,
  label,
  subLabel,
  value,
}: {
  checked?: boolean
  disabled?: boolean
  disabledTooltip?: string
  label: string
  subLabel: string
  value: string
}) {
  const radioControl = (
    <FormControl disabled={disabled}>
      <Radio checked={checked} value={value} className={styles.Radio} />
      <FormControl.Label className="d-flex flex-column">
        <span>{label}</span>
        <span className={styles.RadioText}>{subLabel}</span>
      </FormControl.Label>
    </FormControl>
  )

  return disabled && disabledTooltip ? <Tooltip text={disabledTooltip}>{radioControl}</Tooltip> : radioControl
}

export function ReviewMenuButton({
  diffEntries,
  commentBoxConfig,
  commentBoxSubject,
  currentUserLogin,
  pullRequest,
  repository,
  redirectOnMutation = true,
  tabSize,
}: ReviewMenuButtonProps) {
  const {
    author,
    pathName,
    state,
    viewerAllowedNonCommentReviewTypes,
    viewerHasViolatedPushPolicy,
    viewerIsCopilotAttributed,
    comparison,
  } = pullRequest

  const {data: pendingCommentData} = usePendingReviewPageData({
    pathName,
  })

  const {persistedReview, persistReviewToStorage, removePersistedReviewFromStorage} = usePersistedReview(pathName)

  const commentsList = useGenerateThreadPreviews(
    pendingCommentData?.pendingReviewIDs ?? [],
    pullRequest.pathName,
    diffEntries,
    pendingCommentData?.comments,
  )

  const totalPendingComments = commentsList?.length ?? 0

  // We will probably want to use CurrentUserContext and useCurrentUser
  const viewerIsAuthor = author?.login === currentUserLogin
  const isPROpen = state !== PullRequestState.Closed && state !== PullRequestState.Merged
  const viewerCanWriteToRepo = repository.viewerPermission === 'WRITE' || repository.viewerPermission === 'ADMIN'
  const headRefOid = comparison.headOid
  const markdownInputRef = useRef<CommentBoxHandle>(null)
  const [isOpen, setIsOpen] = useSafeState(false)
  const [isSubmitting, setIsSubmitting] = useSafeState(false)
  const [isCancelling, setIsCancelling] = useSafeState(false)
  const [errorMessage, setErrorMessage] = useSafeState<string | undefined>()
  const [reviewEvent, setReviewEvent] = useSafeState<ReviewEvent>(persistedReview?.event ?? ReviewEvent.comment)

  // ref and state to keep track of the review body without causing re-renders
  // we ultimately only care about the final value when submitting the review and validating review body presence
  const initialReviewBody = persistedReview?.text ?? ''
  const reviewBodyRef = useRef<string>(initialReviewBody)
  const [hasReviewBody, setHasReviewBody] = useSafeState<boolean>(!!persistedReview?.text)

  const submitDisabled =
    isSubmitting || (!hasReviewBody && reviewEvent === ReviewEvent.comment && !totalPendingComments)

  const {sendPullRequestAnalyticsEvent} = usePullRequestToolbarAnalytics()

  useEffect(() => {
    if (isOpen) {
      const timeout = window.setTimeout(() => markdownInputRef.current?.focus())
      return () => {
        window.clearTimeout(timeout)
      }
    }
  }, [isOpen])

  const onReviewBodyChange = (body: string) => {
    reviewBodyRef.current = body
    setHasReviewBody(!!body.trim())
    persistReviewToStorage(reviewEvent, body)
  }

  const handleReviewEventChange = (newReviewEvent: string | null) => {
    if (Object.values(ReviewEvent).includes(newReviewEvent as ReviewEvent)) {
      setReviewEvent(newReviewEvent as ReviewEvent)
      persistReviewToStorage(newReviewEvent as ReviewEvent, reviewBodyRef.current)
    }
  }

  const {mutate: submitReview} = useSubmitReviewMutation({
    onSuccess: ({redirectUrl}: ReviewResponse) => {
      removePersistedReviewFromStorage()
      // eslint-disable-next-line react-hooks/react-compiler
      if (redirectOnMutation) window.location.href = redirectUrl
    },
    onError: (error: Error) => {
      setIsSubmitting(false)

      // TODO: add better error handling responses here based on message from server
      setErrorMessage(error.message)
    },
  })

  const {mutate: abandonReview} = useAbandonReviewMutation({
    onSuccess: ({redirectUrl}: ReviewResponse) => {
      removePersistedReviewFromStorage()
      if (redirectOnMutation) window.location.href = redirectUrl
    },
    onError: (error: Error) => {
      setIsCancelling(false)

      // TODO: add better error handling responses here based on message from server
      setErrorMessage(error.message)
    },
  })

  const handleReviewSubmit = () => {
    if (errorMessage) setErrorMessage(undefined)
    setIsSubmitting(true)
    sendPullRequestAnalyticsEvent('submit_review_dialog.submit', 'SUBMIT_REVIEW_BUTTON')
    submitReview({
      body: reviewBodyRef.current,
      event: reviewEvent,
      headSha: headRefOid,
    })
  }

  const handleReviewCancel = () => {
    if ((pendingCommentData?.pendingReviewIDs ?? []).length === 0) return
    if (!confirm('Are you sure you want to cancel? You will lose all your pending comments.')) return

    if (errorMessage) setErrorMessage(undefined)

    setIsCancelling(true)
    sendPullRequestAnalyticsEvent('submit_review_dialog.cancel', 'CANCEL_REVIEW_BUTTON')
    abandonReview()
  }

  const reviewMenuButtonDisplayState = useMemo(
    () =>
      getReviewMenuButtonDisplayState({
        isPROpen,
        viewerAllowedNonCommentReviewTypes,
        viewerIsAuthor,
        totalPendingComments,
      }),
    [viewerAllowedNonCommentReviewTypes, totalPendingComments, isPROpen, viewerIsAuthor],
  )

  const handleOpenReviewDialog = useCallback(() => {
    setIsOpen(true)
    sendPullRequestAnalyticsEvent('submit_review_dialog.open', 'REVIEW_CHANGES_BUTTON')
  }, [setIsOpen, sendPullRequestAnalyticsEvent])

  const handleCloseReviewDialog = useCallback(() => {
    setIsOpen(false)
  }, [setIsOpen])

  const handleNavigateToDiffComment = useCallback(() => {
    setIsOpen(false)
  }, [setIsOpen])

  if (reviewMenuButtonDisplayState.isHidden) return null

  return (
    <>
      <Button
        count={totalPendingComments ? totalPendingComments : undefined}
        className={styles.ReviewMenuButton}
        trailingAction={TriangleDownIcon}
        variant="primary"
        onClick={handleOpenReviewDialog}
        size="small"
      >
        Submit {reviewMenuButtonDisplayState.text}
      </Button>
      {isOpen && (
        <Dialog
          onClose={handleCloseReviewDialog}
          aria-label="Review changes"
          position={{narrow: 'fullscreen', regular: 'right', wide: 'right'}}
          title={`Finish your ${reviewMenuButtonDisplayState.text}`}
          renderFooter={() => (
            <Dialog.Footer>
              {errorMessage && (
                <Flash className="mx-3 my-2" variant="danger">
                  <StopIcon className="mr-2" />
                  {errorMessage}
                </Flash>
              )}
              <div className="d-flex flex-row flex-1 flex-items-center flex-justify-between">
                {(pendingCommentData?.pendingReviewIDs ?? []).length !== 0 && (
                  <Button
                    className="mx-2"
                    disabled={isCancelling}
                    onClick={handleReviewCancel}
                    tabIndex={0}
                    variant="danger"
                  >
                    <Stack direction="horizontal" align="center">
                      Discard {reviewMenuButtonDisplayState.text}
                      {isCancelling && <Spinner size="small" className="ml-2" />}
                    </Stack>
                  </Button>
                )}
                <div className="d-flex flex-row gap-2">
                  <Button onClick={handleCloseReviewDialog}>Cancel</Button>
                  <Button disabled={submitDisabled} variant="primary" onClick={handleReviewSubmit}>
                    <div className="d-flex flex-row flex-justify-center">
                      Submit {reviewMenuButtonDisplayState.text}
                      {isSubmitting && <Spinner size="small" className="ml-2" />}
                    </div>
                  </Button>
                </div>
              </div>
            </Dialog.Footer>
          )}
        >
          <ControlledCommentBox
            subject={commentBoxSubject}
            ref={markdownInputRef}
            label="Add review comment"
            placeholder="Leave a comment"
            sx={{flexGrow: '1', width: '100%'}}
            userSettings={commentBoxConfig}
            initialValue={initialReviewBody}
            onChange={onReviewBodyChange}
            onPrimaryAction={handleReviewSubmit}
          />
          {isPROpen && (
            <ReviewRadioButtons
              reviewEvent={reviewEvent}
              viewerAllowedNonCommentReviewTypes={viewerAllowedNonCommentReviewTypes}
              viewerCanWriteToRepo={viewerCanWriteToRepo}
              viewerHasViolatedPushPolicy={viewerHasViolatedPushPolicy}
              viewerIsAuthor={viewerIsAuthor}
              viewerIsCopilotAttributed={viewerIsCopilotAttributed}
              onReviewEventChange={handleReviewEventChange}
            />
          )}
          {totalPendingComments ? (
            <>
              <Heading as="h3" className="mt-3 mb-2" variant="small">
                Review comments
              </Heading>
              <Suspense fallback={<Spinner />}>
                <RelayEnvironmentProvider environment={relayEnvironment}>
                  <div className="d-flex flex-column gap-3">
                    {commentsList?.map(preview => (
                      <PendingCommentPreview
                        key={preview.threadId}
                        commentPreview={preview}
                        tabSize={tabSize}
                        onNavigateToDiffComment={handleNavigateToDiffComment}
                      />
                    ))}
                  </div>
                </RelayEnvironmentProvider>
              </Suspense>
            </>
          ) : null}
        </Dialog>
      )}
    </>
  )
}

/**
 * ControlledCommentBox is a wrapper around ConversationCommentBox that allows
 * it to be controlled by an initial value and an onChange callback.
 * This is useful for cases where you want to manage the comment box state
 * outside of the component to prevent unnecessary re-renders on every keystroke.
 */
const ControlledCommentBox = forwardRef<
  CommentBoxHandle,
  Omit<ConversationCommentBoxProps, 'value'> & {
    initialValue: string
    onChange: (value: string) => void
  }
>(({initialValue, onChange, ...props}, ref) => {
  const [reviewBody, setReviewBody] = useSafeState<string>(initialValue)

  const onCommentBoxChange = useCallback(
    (value: string) => {
      setReviewBody(value)
      onChange(value)
    },
    [setReviewBody, onChange],
  )

  return <ConversationCommentBox {...props} value={reviewBody} onChange={onCommentBoxChange} ref={ref} />
})

ControlledCommentBox.displayName = 'ControlledCommentBox'

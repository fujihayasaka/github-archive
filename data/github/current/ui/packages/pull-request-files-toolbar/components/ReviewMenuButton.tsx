import type {CommentBoxConfig, CommentBoxHandle} from '@github-ui/comment-box/CommentBox'
import type {CommentingAppPayload} from '@github-ui/commenting/Types'
import {ConversationCommentBox} from '@github-ui/conversations'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import useSafeState from '@github-ui/use-safe-state'
import {StopIcon, TriangleDownIcon} from '@primer/octicons-react'
import {Box, Button, Dialog, Flash, FormControl, Heading, Radio, RadioGroup, Spinner, Text} from '@primer/react'
import {Octicon, Tooltip} from '@primer/react/deprecated'
import {Suspense, useEffect, useMemo, useRef} from 'react'
import {capitalize} from '@github-ui/filter/utils'

import {usePullRequestToolbarAnalytics} from '../hooks/use-pull-request-toolbar-analytics'
import {PullRequestState, type PullRequest, type Repository} from '../page-data/payloads/toolbar'
import {useSubmitReviewMutation, ReviewEvent} from '../hooks/mutations/use-submit-review-mutation'
import type {ReviewResponse} from '../page-data/payloads/review-response'
import {useAbandonReviewMutation} from '../hooks/mutations/use-abandon-review-mutation'
import {PendingCommentPreview} from './PendingCommentPreview'
import {RelayEnvironmentProvider} from 'react-relay'
import {relayEnvironmentWithMissingFieldHandlerForNode} from '@github-ui/relay-environment'
import {usePendingReviewPageData, type PendingReview} from '../page-data/payloads/pending-review'
import {usePersistedReview} from '../hooks/use-persisted-review-data'
import styles from './ReviewMenuButton.module.css'

const relayEnvironment = relayEnvironmentWithMissingFieldHandlerForNode()

export type RepositoryPermission = 'ADMIN' | 'MAINTAIN' | 'READ' | 'TRIAGE' | 'WRITE'

export interface ReviewMenuButtonProps {
  currentUserLogin: string
  initialPendingReview: PendingReview
  pullRequest: PullRequest
  repository: Repository
  redirectOnMutation?: boolean
  tabSize?: number
}

function getApproveDisabledTooltip(
  reviewerIsAuthor: boolean,
  violatedPushPolicy: boolean,
  canLeaveNonCommentReview: boolean,
) {
  if (reviewerIsAuthor) return "Pull request authors can't approve their own pull requests."
  if (violatedPushPolicy) return "Users that pushed changes to this pull request after it was opened can't approve"
  if (!canLeaveNonCommentReview) return 'Only users with explicit access to this repository may approve pull requests'
  return ''
}

function getRequestChangesDisabledTooltip(reviewerIsAuthor: boolean, canLeaveNonCommentReview: boolean) {
  if (reviewerIsAuthor) return "Pull request authors can't request changes on their own pull requests."
  if (!canLeaveNonCommentReview)
    return 'Only users with explicit access to this repository may request changes on pull requests'
  return ''
}

function getReviewMenuButtonDisplayState({
  totalPendingComments,
  viewerIsAuthor,
  viewerCanLeaveNonCommentReviews,
  isPROpen,
}: {
  totalPendingComments?: number
  viewerIsAuthor: boolean
  viewerCanLeaveNonCommentReviews: boolean
  isPROpen: boolean
}): {isHidden: boolean; text?: string} {
  const hasPendingComments = (totalPendingComments ?? 0) > 0
  const isCommentingAuthor = viewerIsAuthor && hasPendingComments
  const isApprovingReviewer = viewerCanLeaveNonCommentReviews
  const isNonApprovingReviewerWithComments = !isApprovingReviewer && hasPendingComments
  const isNonApprovingReviewerWithoutComments = !isApprovingReviewer && !hasPendingComments

  switch (true) {
    case !isPROpen:
      return {
        isHidden: !hasPendingComments,
        text: 'comments',
      }
    case isCommentingAuthor || isNonApprovingReviewerWithComments:
      return {
        isHidden: false,
        text: 'comments',
      }
    case isApprovingReviewer:
      return {
        isHidden: false,
        text: 'review',
      }
    case isNonApprovingReviewerWithoutComments:
    default:
      return {isHidden: true}
  }
}

function ReviewRadioButtons({
  onReviewEventChange,
  reviewEvent,
  viewerCanLeaveNonCommentReviews,
  viewerCanWriteToRepo,
  viewerHasViolatedPushPolicy,
  viewerIsAuthor,
}: {
  onReviewEventChange: (selected: string | null) => void
  reviewEvent: ReviewEvent
  viewerCanLeaveNonCommentReviews: boolean
  viewerCanWriteToRepo: boolean
  viewerHasViolatedPushPolicy: boolean | null | undefined
  viewerIsAuthor: boolean
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
        disabled={!viewerCanLeaveNonCommentReviews}
        label={capitalize(ReviewEvent.approve)}
        subLabel="Submit feedback and approve merging these changes."
        value={ReviewEvent.approve}
        disabledTooltip={getApproveDisabledTooltip(
          viewerIsAuthor,
          !!viewerHasViolatedPushPolicy,
          viewerCanLeaveNonCommentReviews,
        )}
      />
      <RadioButton
        checked={reviewEvent === ReviewEvent.requestChanges}
        disabled={!viewerCanLeaveNonCommentReviews}
        disabledTooltip={getRequestChangesDisabledTooltip(viewerIsAuthor, viewerCanLeaveNonCommentReviews)}
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
}

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
      <FormControl.Label sx={{display: 'flex', flexDirection: 'column'}}>
        <span>{label}</span>
        <Text sx={{color: 'fg.muted', fontWeight: 'normal', fontSize: 0}}>{subLabel}</Text>
      </FormControl.Label>
    </FormControl>
  )

  return disabled && disabledTooltip ? <Tooltip text={disabledTooltip}>{radioControl}</Tooltip> : radioControl
}

export function ReviewMenuButton({
  currentUserLogin,
  initialPendingReview,
  pullRequest,
  repository,
  redirectOnMutation = true,
  tabSize,
}: ReviewMenuButtonProps) {
  const {author, pathName, state, viewerCanLeaveNonCommentReviews, viewerHasViolatedPushPolicy, comparison} =
    pullRequest

  const pageData = usePendingReviewPageData({
    pathName,
    initialData: initialPendingReview,
  })

  const {persistedReview, persistReviewToStorage, removePersistedReviewFromStorage} = usePersistedReview(pathName)

  const viewerPendingReview = pageData?.data

  const totalPendingComments = viewerPendingReview?.comments.length ?? 0

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
  const [reviewBody, setReviewBody] = useSafeState<string>(persistedReview?.text ?? '')
  const [reviewEvent, setReviewEvent] = useSafeState<ReviewEvent>(persistedReview?.event ?? ReviewEvent.comment)

  const submitDisabled = isSubmitting || (!reviewBody && reviewEvent === ReviewEvent.comment && !totalPendingComments)

  const {sendPullRequestAnalyticsEvent} = usePullRequestToolbarAnalytics()
  const appPayload = useAppPayload<CommentingAppPayload>()
  const pasteUrlsAsPlainText = appPayload?.paste_url_link_as_plain_text || false
  const useMonospaceFont = appPayload?.current_user_settings?.use_monospace_font || false
  const commentBoxConfig: CommentBoxConfig = {
    pasteUrlsAsPlainText,
    useMonospaceFont,
  }

  useEffect(() => {
    if (isOpen) {
      const timeout = window.setTimeout(() => markdownInputRef.current?.focus())
      return () => {
        window.clearTimeout(timeout)
      }
    }
  }, [isOpen])

  const onReviewBodyChange = (body: string) => {
    setReviewBody(body)
    persistReviewToStorage(reviewEvent, body)
  }

  const handleReviewEventChange = (newReviewEvent: string | null) => {
    if (Object.values(ReviewEvent).includes(newReviewEvent as ReviewEvent)) {
      setReviewEvent(newReviewEvent as ReviewEvent)
      persistReviewToStorage(newReviewEvent as ReviewEvent, reviewBody)
    }
  }

  const {mutate: submitReview} = useSubmitReviewMutation({
    onSuccess: ({redirectUrl}: ReviewResponse) => {
      removePersistedReviewFromStorage()
      // eslint-disable-next-line react-compiler/react-compiler
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
      body: reviewBody,
      event: reviewEvent,
      headSha: headRefOid,
    })
  }

  const handleReviewCancel = () => {
    if (!viewerPendingReview?.id) return
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
        viewerCanLeaveNonCommentReviews,
        viewerIsAuthor,
        totalPendingComments,
      }),
    [viewerCanLeaveNonCommentReviews, totalPendingComments, isPROpen, viewerIsAuthor],
  )

  if (reviewMenuButtonDisplayState.isHidden) return null

  return (
    <>
      <Button
        count={totalPendingComments ? totalPendingComments : undefined}
        sx={{'[data-component=trailingIcon]': {marginX: -1}}}
        trailingAction={TriangleDownIcon}
        variant="primary"
        onClick={() => {
          setIsOpen(true)
          sendPullRequestAnalyticsEvent('submit_review_dialog.open', 'REVIEW_CHANGES_BUTTON')
        }}
        size="small"
      >
        Submit {reviewMenuButtonDisplayState.text}
      </Button>
      {isOpen && (
        <Dialog
          onClose={() => setIsOpen(false)}
          aria-label="Review changes"
          position={{narrow: 'fullscreen', regular: 'right', wide: 'right'}}
          title={`Finish your ${reviewMenuButtonDisplayState.text}`}
          renderFooter={() => (
            <Dialog.Footer>
              {errorMessage && (
                <Flash className="mx-3 my-2" variant="danger">
                  <Octicon className="mr-2" icon={StopIcon} />
                  {errorMessage}
                </Flash>
              )}
              <div className="d-flex flex-row flex-1 flex-items-center flex-justify-between">
                {viewerPendingReview?.id && (
                  <Button
                    className="mx-2"
                    disabled={isCancelling}
                    onClick={handleReviewCancel}
                    tabIndex={0}
                    variant="danger"
                  >
                    <Box sx={{alignItems: 'center', display: 'flex', flexDirection: 'row'}}>
                      Discard {reviewMenuButtonDisplayState.text}
                      {isCancelling && <Spinner size="small" sx={{ml: 2}} />}
                    </Box>
                  </Button>
                )}
                <div className="d-flex flex-row gap-2">
                  <Button onClick={() => setIsOpen(false)}>Cancel</Button>
                  <Button disabled={submitDisabled} variant="primary" onClick={handleReviewSubmit}>
                    <div className="d-flex flex-row flex-justify-center">
                      Submit {reviewMenuButtonDisplayState.text}
                      {isSubmitting && <Spinner size="small" sx={{ml: 2}} />}
                    </div>
                  </Button>
                </div>
              </div>
            </Dialog.Footer>
          )}
        >
          <ConversationCommentBox
            ref={markdownInputRef}
            label="Add review comment"
            placeholder="Leave a comment"
            sx={{flexGrow: '1', width: '100%'}}
            userSettings={commentBoxConfig}
            value={reviewBody}
            onChange={onReviewBodyChange}
            onPrimaryAction={handleReviewSubmit}
          />
          {isPROpen && (
            <ReviewRadioButtons
              reviewEvent={reviewEvent}
              viewerCanLeaveNonCommentReviews={viewerCanLeaveNonCommentReviews}
              viewerCanWriteToRepo={viewerCanWriteToRepo}
              viewerHasViolatedPushPolicy={viewerHasViolatedPushPolicy}
              viewerIsAuthor={viewerIsAuthor}
              onReviewEventChange={handleReviewEventChange}
            />
          )}
          {totalPendingComments ? (
            <>
              <Heading as="h3" sx={{mt: 3, mb: 2}} variant="small">
                Review comments
              </Heading>
              <Suspense fallback={<Spinner />}>
                <RelayEnvironmentProvider environment={relayEnvironment}>
                  <div className="d-flex flex-column gap-3">
                    {viewerPendingReview?.comments.map(preview => (
                      <PendingCommentPreview
                        key={preview.id}
                        commentPreview={preview}
                        tabSize={tabSize}
                        onNavigateToDiffComment={() => setIsOpen(false)}
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

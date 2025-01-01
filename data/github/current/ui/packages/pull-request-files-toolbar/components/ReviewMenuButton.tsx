import type {CommentBoxConfig, CommentBoxHandle} from '@github-ui/comment-box/CommentBox'
import type {CommentingAppPayload} from '@github-ui/commenting/Types'
import {ConversationCommentBox} from '@github-ui/conversations'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import useSafeState from '@github-ui/use-safe-state'
import {StopIcon, TriangleDownIcon, XIcon} from '@primer/octicons-react'
import {
  AnchoredOverlay,
  Box,
  Button,
  Flash,
  FormControl,
  Heading,
  IconButton,
  Radio,
  RadioGroup,
  Spinner,
  Text,
} from '@primer/react'
import {Octicon, Tooltip} from '@primer/react/deprecated'
import {useEffect, useMemo, useRef} from 'react'

import {usePullRequestToolbarAnalytics} from '../hooks/use-pull-request-toolbar-analytics'

export type RepositoryPermission = 'ADMIN' | 'MAINTAIN' | 'READ' | 'TRIAGE' | 'WRITE'
export type PullRequestReviewEvent = 'APPROVE' | 'COMMENT' | 'DISMISS' | 'REQUEST_CHANGES'

export type AddReviewCallback = (
  body: string,
  event: PullRequestReviewEvent,
  pullRequestId: string,
  commitOID: string,
) => ReviewMenuButtonActionResponse

export type CancelReviewCallback = (
  pullRequestId: string,
  pullRequestReviewId: string,
) => ReviewMenuButtonActionResponse

export type SubmitReviewCallback = (
  body: string,
  event: PullRequestReviewEvent,
  pullRequestId: string,
  pullRequestReviewId: string,
  commitOID: string,
) => ReviewMenuButtonActionResponse

export type PendingViewerReview = {id: string; comments: {totalCount: number}}

export interface PullRequestData {
  author: {login: string}
  headRefOid: string
  id: string
  repository: {viewerPermission: string}
  state: string
  viewerCanLeaveNonCommentReviews: boolean
  viewerHasViolatedPushPolicy: boolean
  comparison: {newCommit: {oid: string}} | null
}

export interface ReviewMenuButtonProps {
  pullRequest: PullRequestData
  onAddReview: AddReviewCallback
  onCancelReview: CancelReviewCallback
  onSumbitReview: SubmitReviewCallback
  onUpdateReviewBody: (body: string) => void
  onUpdateReviewEvent: (body: string) => void
  redirectOnSubmit?: boolean
  reviewBody: string
  reviewEvent: string
  currentUserLogin: string
  viewerPendingReview?: PendingViewerReview
}

interface ReviewMenuButtonActionResponse {
  success: boolean
  errorMessage?: string
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

function getPendingCommentMessage(count: number) {
  if (count === 0) return ''
  if (count === 1) return '1 pending comment'
  return `${count} pending comments`
}

function getReviewMenuButtonDisplayState({
  viewerIsAuthor,
  viewerCanLeaveNonCommentReviews,
  isPROpen,
  viewerPendingReview,
}: {
  viewerIsAuthor: boolean
  viewerCanLeaveNonCommentReviews: boolean
  isPROpen: boolean
  viewerPendingReview?: {comments: {totalCount: number}} | null
}): {isHidden: boolean; text?: string} {
  const hasPendingComments = (viewerPendingReview?.comments.totalCount ?? 0) > 0
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
  reviewEvent: string
  viewerCanLeaveNonCommentReviews: boolean
  viewerCanWriteToRepo: boolean
  viewerHasViolatedPushPolicy: boolean | null | undefined
  viewerIsAuthor: boolean
}) {
  return (
    <RadioGroup name="reviewEvent" sx={{mt: 3}} onChange={onReviewEventChange}>
      <RadioGroup.Label visuallyHidden>Review Event</RadioGroup.Label>
      <RadioButton
        checked={reviewEvent === 'COMMENT'}
        label="Comment"
        subLabel="Submit general feedback without explicit approval."
        value="COMMENT"
      />
      <RadioButton
        checked={reviewEvent === 'APPROVE'}
        disabled={!viewerCanLeaveNonCommentReviews}
        label="Approve"
        subLabel="Submit feedback and approve merging these changes."
        value="APPROVE"
        disabledTooltip={getApproveDisabledTooltip(
          viewerIsAuthor,
          !!viewerHasViolatedPushPolicy,
          viewerCanLeaveNonCommentReviews,
        )}
      />
      <RadioButton
        checked={reviewEvent === 'REQUEST_CHANGES'}
        disabled={!viewerCanLeaveNonCommentReviews}
        disabledTooltip={getRequestChangesDisabledTooltip(viewerIsAuthor, viewerCanLeaveNonCommentReviews)}
        label="Request changes"
        value="REQUEST_CHANGES"
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
      <Radio checked={checked} sx={{mt: 1}} value={value} />
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
  pullRequest,
  onAddReview,
  onCancelReview,
  onSumbitReview,
  onUpdateReviewBody,
  onUpdateReviewEvent,
  reviewEvent,
  reviewBody,
  viewerPendingReview,
}: ReviewMenuButtonProps) {
  const {
    author,
    id,
    repository,
    state,
    viewerCanLeaveNonCommentReviews,
    viewerHasViolatedPushPolicy,
    comparison,
    ...rest
  } = pullRequest

  // We will probably want to use CurrentUserContext and useCurrentUser
  const viewerIsAuthor = author?.login === currentUserLogin
  const isPROpen = state === 'OPEN'
  const viewerCanWriteToRepo = repository.viewerPermission === 'WRITE' || repository.viewerPermission === 'ADMIN'
  const headRefOid = comparison?.newCommit?.oid ?? rest.headRefOid
  const markdownInputRef = useRef<CommentBoxHandle>(null)
  const [isOpen, setIsOpen] = useSafeState(false)
  const [isSubmitting, setIsSubmitting] = useSafeState(false)
  const [isCancelling, setIsCancelling] = useSafeState(false)
  const [errorMessage, setErrorMessage] = useSafeState<string | undefined>()
  const submitDisabled =
    isSubmitting || (!reviewBody && reviewEvent === 'COMMENT' && !viewerPendingReview?.comments.totalCount)

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

  const handleReviewEventChange = (newReviewEvent: string | null) => {
    if (newReviewEvent) onUpdateReviewEvent(newReviewEvent)
  }

  const handleReviewSubmit = () => {
    if (errorMessage) setErrorMessage(undefined)
    setIsSubmitting(true)

    const commonInput = {body: reviewBody, event: reviewEvent as PullRequestReviewEvent, pullRequestId: id}

    const onError = (error: string) => {
      setIsSubmitting(false)
      const additionalErrorText = error ? `: ${error}` : '.'
      setErrorMessage(`Failed to submit review${additionalErrorText}`)
    }

    if (viewerPendingReview) {
      const result = onSumbitReview(
        commonInput.body,
        commonInput.event,
        commonInput.pullRequestId,
        viewerPendingReview.id,
        headRefOid,
      )

      if (result.success) {
        setIsSubmitting(false)
        setIsOpen(false)
        onUpdateReviewBody('')
      } else {
        onError(result.errorMessage ?? '')
      }
    } else {
      const result = onAddReview(commonInput.body, commonInput.event, commonInput.pullRequestId, headRefOid)

      if (result.success) {
        setIsSubmitting(false)
        setIsOpen(false)
        onUpdateReviewBody('')
      } else {
        onError(result.errorMessage ?? '')
      }
    }
    sendPullRequestAnalyticsEvent('submit_review_dialog.submit', 'SUBMIT_REVIEW_BUTTON')
  }

  const handleReviewCancel = () => {
    if (!viewerPendingReview) return
    if (!confirm('Are you sure you want to cancel? You will lose all your pending comments.')) return

    if (errorMessage) setErrorMessage(undefined)
    setIsCancelling(true)

    const result = onCancelReview(id, viewerPendingReview.id)

    if (result.success) {
      setIsCancelling(false)
      setIsOpen(false)
      onUpdateReviewBody('')
    } else {
      setIsCancelling(false)
      setErrorMessage(`Failed to cancel review: ${result.errorMessage}`)
    }
    sendPullRequestAnalyticsEvent('submit_review_dialog.cancel', 'CANCEL_REVIEW_BUTTON')
  }

  const reviewMenuButtonDisplayState = useMemo(
    () =>
      getReviewMenuButtonDisplayState({
        isPROpen,
        viewerCanLeaveNonCommentReviews,
        viewerIsAuthor,
        viewerPendingReview,
      }),
    [viewerCanLeaveNonCommentReviews, viewerPendingReview, isPROpen, viewerIsAuthor],
  )
  if (reviewMenuButtonDisplayState.isHidden) return null

  return (
    <AnchoredOverlay
      // just let the browser's default tab behavior take over
      focusZoneSettings={{disabled: true}}
      open={isOpen}
      overlayProps={{
        sx: {
          display: 'flex',
          maxWidth: 'calc(100vw - 32px)',
          width: '640px',
          // Action menu overlay has a child div that needs to flex grow
          '& > div': {flexGrow: '1'},
        },
      }}
      renderAnchor={anchorProps => (
        <Button
          {...anchorProps}
          count={viewerPendingReview?.comments.totalCount ? viewerPendingReview.comments.totalCount : undefined}
          sx={{'[data-component=trailingIcon]': {marginX: -1}}}
          trailingAction={TriangleDownIcon}
          variant="primary"
        >
          Submit {reviewMenuButtonDisplayState.text}
        </Button>
      )}
      onClose={() => setIsOpen(false)}
      onOpen={() => {
        setIsOpen(true)
        sendPullRequestAnalyticsEvent('submit_review_dialog.open', 'REVIEW_CHANGES_BUTTON')
      }}
    >
      <div className="d-flex flex-column">
        <div className="mt-2 mx-3 mb-0">
          <div className="d-flex flex-justify-between flex-items-center mb-2">
            <Heading as="h4" className="f5">
              <span>Finish your {reviewMenuButtonDisplayState.text}</span>
            </Heading>
            {/* eslint-disable-next-line primer-react/a11y-remove-disable-tooltip */}
            <IconButton
              aria-label="Close"
              icon={XIcon}
              unsafeDisableTooltip
              variant="invisible"
              onClick={() => setIsOpen(false)}
            />
          </div>
          <ConversationCommentBox
            ref={markdownInputRef}
            label="Add review comment"
            placeholder="Leave a comment"
            sx={{flexGrow: '1', width: '100%'}}
            userSettings={commentBoxConfig}
            value={reviewBody}
            onChange={onUpdateReviewBody}
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
        </div>

        <div className="my-3 border-top">
          {errorMessage && (
            <Flash className="mx-3 my-2" variant="danger">
              <Octicon className="mr-2" icon={StopIcon} />
              {errorMessage}
            </Flash>
          )}
          <div className="d-flex flex-row flex-items-center flex-justify-end mt-3 mx-3">
            {viewerPendingReview?.id && (
              <>
                <div className="ml-2 fgColor-muted f6">
                  {getPendingCommentMessage(viewerPendingReview.comments.totalCount)}
                </div>
                <Button className="mx-2" disabled={isCancelling} tabIndex={0} onClick={handleReviewCancel}>
                  <Box sx={{alignItems: 'center', display: 'flex', flexDirection: 'row'}}>
                    Discard {reviewMenuButtonDisplayState.text}
                    {isCancelling && <Spinner size="small" sx={{ml: 2}} />}
                  </Box>
                </Button>
              </>
            )}
            <Button disabled={submitDisabled} variant="primary" onClick={handleReviewSubmit}>
              <div className="d-flex flex-row flex-justify-center">
                Submit {reviewMenuButtonDisplayState.text}
                {isSubmitting && <Spinner size="small" sx={{ml: 2}} />}
              </div>
            </Button>
          </div>
        </div>
      </div>
    </AnchoredOverlay>
  )
}

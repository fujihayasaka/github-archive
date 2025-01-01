import {ListItem} from '@github-ui/list-view/ListItem'
import {ListItemTitle} from '@github-ui/list-view/ListItemTitle'
import {ListItemLeadingVisual} from '@github-ui/list-view/ListItemLeadingVisual'

import {GitHubAvatar} from '@github-ui/github-avatar'
import {clsx} from 'clsx'
import sectionListItemStyles from '../common/SectionListItem.module.css'
import styles from '../ReviewerSection.module.css'
import {ActionList, Flash, FormControl, Textarea} from '@primer/react'
import {Dialog} from '@primer/react/experimental'
import {useCallback, useEffect, useRef, useState} from 'react'
import {useDismissReviewMutation} from '../../../hooks/mutations/use-dismiss-review-mutation'
import {useReRequestReviewFromUser} from '../../../hooks/mutations/use-re-request-review-from-user'
import {ListItemActionBar} from '@github-ui/list-view/ListItemActionBar'
import {StopIcon} from '@primer/octicons-react'
import {Octicon} from '@primer/react/deprecated'
import type {SafeHTMLString} from '@github-ui/safe-html'

interface ReviewListItemProps {
  reviewer: {
    login: string
    url: string
    avatarUrl: string
    name: string
  }
  reviewStatusText: string
  hovercardUrl: string
  reviewId?: number
  viewerCanDismissReviews?: boolean
  viewerCanReRequestReviews?: boolean
}

export function ReviewListItem({
  reviewer,
  reviewStatusText,
  hovercardUrl,
  reviewId,
  viewerCanDismissReviews,
  viewerCanReRequestReviews = false,
}: ReviewListItemProps) {
  const textAreaRef = useRef<HTMLTextAreaElement>(null)
  const anchorRef = useRef<HTMLButtonElement>(null)

  const [showDismissReviewDialog, setShowDismissReviewDialog] = useState(false)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const [dismissalMessage, setDismissalMessage] = useState('')
  const hasValidationErrors = dismissalMessage.trim().length < 1
  const [shouldShowValidationErrors, setShouldShowValidationErrors] = useState(false)

  const dismissReviewOption = {
    key: 'dismiss-review',
    render: () => (
      <ActionList.Item
        onSelect={() => {
          setShowDismissReviewDialog(true)
        }}
      >
        Dismiss review
      </ActionList.Item>
    ),
  }

  const reRequestReviewOption = {
    key: 're-request-review',
    render: () => (
      <ActionList.Item onSelect={() => reRequestReviewFromUser({reviewerLogin: reviewer.login})}>
        Re-request review
      </ActionList.Item>
    ),
  }

  const menuActions = [
    viewerCanDismissReviews ? dismissReviewOption : null,
    viewerCanReRequestReviews ? reRequestReviewOption : null,
  ].filter(action => !!action)
  const showReviewOptions = !!reviewId && menuActions.length > 0

  const closeDismissReviewDialog = async () => {
    setErrorMessage(null)
    setShowDismissReviewDialog(false)
    setShouldShowValidationErrors(false)
    anchorRef.current?.focus()
  }

  const handleDismissalMessageChange = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    setShouldShowValidationErrors(false)
    setDismissalMessage(e.target.value)
  }

  const {mutate: reRequestReviewFromUser} = useReRequestReviewFromUser({
    onError: () => {
      // TODO: Display error message somewhere instead of in an alert
      // See issue: https://github.com/github/pull-requests/issues/15051
    },
  })

  const {mutate: dismissReview, isPending} = useDismissReviewMutation()

  const submitDismissReview = useCallback(() => {
    if (isPending) return

    if (hasValidationErrors) {
      setShouldShowValidationErrors(true)
    }

    if (reviewId && !hasValidationErrors) {
      dismissReview(
        {reviewId, message: dismissalMessage},
        {
          onSuccess: () => {
            closeDismissReviewDialog()
          },
          onError: (e: Error) => {
            setErrorMessage(e.message)
          },
        },
      )
    }
  }, [dismissReview, dismissalMessage, hasValidationErrors, isPending, reviewId])

  // gives the user the abilty to dismiss a review by pressing cmd+enter
  useEffect(() => {
    function handleKeyDown(event: KeyboardEvent) {
      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      if (event.metaKey && event.key === 'Enter' && showDismissReviewDialog) {
        event.preventDefault()
        submitDismissReview()
      }
    }

    document.addEventListener('keydown', handleKeyDown)

    return () => {
      document.removeEventListener('keydown', handleKeyDown)
    }
  }, [showDismissReviewDialog, submitDismissReview])

  if (!reviewer) return null

  const listItemAriaLabel = `${reviewer.login} ${reviewStatusText.charAt(0).toLowerCase() + reviewStatusText.slice(1)}`

  return (
    <>
      <ListItem
        className={sectionListItemStyles.listItem}
        aria-label={listItemAriaLabel}
        title={
          <ListItemTitle
            href={reviewer.url}
            // markdownValue is a hack to prevent activating navigation to the main item when the secondary actions are opened
            markdownValue={reviewer.login as SafeHTMLString}
            value={reviewer.login}
            containerClassName="d-flex flex-items-center pt-0"
            headingClassName={styles.reviewAuthor}
            anchorClassName={styles.reviewAuthorAnchor}
            leadingBadge={
              <ListItemLeadingVisual className={clsx(styles.leadingVisual, 'mt-1')}>
                <GitHubAvatar
                  alt={`${reviewer.login}'s avatar image`}
                  size={20}
                  src={reviewer.avatarUrl}
                  data-hovercard-url={hovercardUrl}
                  className="flex-shrink-0 ml-2"
                />
              </ListItemLeadingVisual>
            }
          >
            <span className={styles.reviewText}>{reviewStatusText}</span>
          </ListItemTitle>
        }
        secondaryActions={
          showReviewOptions ? (
            <ListItemActionBar
              anchorRef={anchorRef}
              label="review options"
              staticMenuActions={menuActions}
              className={styles.reviewerActionBar}
            />
          ) : undefined
        }
      />
      {showDismissReviewDialog && (
        <Dialog
          title="Dismiss review"
          onClose={closeDismissReviewDialog}
          role="dialog"
          initialFocusRef={textAreaRef}
          returnFocusRef={anchorRef}
          footerButtons={[
            {buttonType: 'default', content: 'Cancel', onClick: closeDismissReviewDialog},
            {
              buttonType: 'danger',
              loading: isPending,
              loadingAnnouncement: 'Dismissing review',
              content: 'Dismiss review',
              onClick: submitDismissReview,
            },
          ]}
        >
          {errorMessage && (
            <Flash className="mb-2" variant="danger">
              <Octicon className="mr-2" icon={StopIcon} />
              {errorMessage}
            </Flash>
          )}
          <FormControl required className="mb-2">
            <FormControl.Label>
              <h4 className="f5">Reason for dismissing {reviewer.login}&apos;s review</h4>
            </FormControl.Label>
            <Textarea
              ref={textAreaRef}
              onChange={handleDismissalMessageChange}
              value={dismissalMessage}
              className="width-full height-full"
            />
            {hasValidationErrors && shouldShowValidationErrors && (
              <FormControl.Validation variant="error">
                Please provide a reason for dismissing the review
              </FormControl.Validation>
            )}
            <FormControl.Caption>
              This reason will appear in the timeline so other users will know why the review was dismissed.
            </FormControl.Caption>
          </FormControl>
        </Dialog>
      )}
    </>
  )
}

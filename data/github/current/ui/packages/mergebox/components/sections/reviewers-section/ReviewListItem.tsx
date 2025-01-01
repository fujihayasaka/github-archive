import {ListItem} from '@github-ui/list-view/ListItem'
import {ListItemTitle} from '@github-ui/list-view/ListItemTitle'
import {ListItemLeadingVisual} from '@github-ui/list-view/ListItemLeadingVisual'

import {GitHubAvatar} from '@github-ui/github-avatar'
import {clsx} from 'clsx'
import sectionListItemStyles from '../common/SectionListItem.module.css'
import styles from '../ReviewerSection.module.css'
import {ListItemTrailingBadge} from '@github-ui/list-view/ListItemTrailingBadge'
import {ActionList, ActionMenu, Button, FormControl, IconButton, Textarea} from '@primer/react'
import {Dialog} from '@primer/react/experimental'
import {KebabHorizontalIcon, XIcon} from '@primer/octicons-react'
import {useEffect, useRef, useState} from 'react'
import {useDismissReviewMutation} from '../../../hooks/mutations/use-dismiss-review-mutation'
import {useReRequestReviewFromUser} from '../../../hooks/mutations/use-re-request-review-from-user'

interface ReviewListItemProps {
  reviewer: {
    login: string
    url: string
    avatarUrl: string
    name: string
  }
  reviewStatusText: string
  hovercardUrl: string
  refetchMergeBoxQuery?: () => void
  reviewId?: number
  showReviewOptions?: boolean
  viewerCanDismissReviews?: boolean
  viewerCanReRequestReviews?: boolean
}

export function ReviewListItem({
  reviewer,
  reviewStatusText,
  hovercardUrl,
  refetchMergeBoxQuery,
  reviewId,
  showReviewOptions = true,
  viewerCanDismissReviews,
  viewerCanReRequestReviews = false,
}: ReviewListItemProps) {
  const [showDialog, setShowDialog] = useState(false)
  const [dialogReviewerLogin, setDialogReviewerLogin] = useState('')
  const [dismissalMessage, setDismissalMessage] = useState('')
  const textAreaRef = useRef<HTMLTextAreaElement>(null)

  const {mutate: reRequestReviewFromUser} = useReRequestReviewFromUser({
    onSuccess: () => {
      refetchMergeBoxQuery?.()
    },
    onError: () => {
      alert('Failed to re-request review')
    },
  })

  const onDialogClose = () => {
    setShowDialog(false)
  }

  const {mutate: dismissReview} = useDismissReviewMutation({
    onSuccess: () => {
      refetchMergeBoxQuery?.()
      onDialogClose()
    },
    onError: () => {
      alert('Failed to dismiss review')
    },
  })

  // gives the user the abilty to dismiss a review by pressing cmd+enter
  useEffect(() => {
    function handleKeyDown(event: KeyboardEvent) {
      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      if (event.metaKey && event.key === 'Enter' && showDialog) {
        event.preventDefault()
        if (reviewId !== undefined) {
          dismissReview({reviewId, message: dismissalMessage})
        } else {
          alert('Review ID is undefined')
        }
        setShowDialog(false)
      }
    }

    document.addEventListener('keydown', handleKeyDown)

    return () => {
      document.removeEventListener('keydown', handleKeyDown)
    }
  }, [showDialog, reviewId, dismissalMessage, dismissReview])

  if (!reviewer) return null

  function dialogHeader() {
    return (
      <div className="d-flex ml-3 mt-2 flex-justify-between">
        <h2> Dismiss Review</h2>
        <IconButton icon={XIcon} aria-label="Close" variant="invisible" onClick={() => setShowDialog(false)} />
      </div>
    )
  }

  return (
    <ListItem
      className={sectionListItemStyles.listItem}
      title={
        <ListItemTitle
          href={reviewer.url}
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
    >
      {showReviewOptions && (
        <ListItemTrailingBadge title="review-options">
          <ActionMenu>
            <ActionMenu.Anchor>
              <IconButton icon={KebabHorizontalIcon} variant="invisible" aria-label="Review options" />
            </ActionMenu.Anchor>
            <ActionMenu.Overlay width="small">
              <ActionList>
                {viewerCanDismissReviews && (
                  <ActionList.Item
                    onSelect={() => {
                      setShowDialog(true)
                      setDialogReviewerLogin(reviewer.login || '')
                    }}
                  >
                    Dismiss review
                  </ActionList.Item>
                )}

                {viewerCanReRequestReviews && (
                  <ActionList.Item onSelect={() => reRequestReviewFromUser({reviewerLogin: reviewer.login})}>
                    Re-request review
                  </ActionList.Item>
                )}
              </ActionList>
            </ActionMenu.Overlay>
          </ActionMenu>
        </ListItemTrailingBadge>
      )}
      {showDialog && (
        <Dialog
          title=""
          renderHeader={dialogHeader}
          onClose={onDialogClose}
          role="dialog"
          initialFocusRef={textAreaRef}
        >
          <FormControl>
            <FormControl.Label>
              <h4>Reason for dismissing</h4>
            </FormControl.Label>
            <Textarea
              ref={textAreaRef}
              onChange={e => setDismissalMessage(e.target.value)}
              className="mt-2 width-full height-full"
              placeholder={`Why are you dismissing ${dialogReviewerLogin}'s review?`}
            />
          </FormControl>
          <Dialog.Footer className="mb-n3 mr-n2">
            <Button variant="default" onClick={() => setShowDialog(false)}>
              Cancel
            </Button>
            <Button
              variant="danger"
              onClick={() => {
                if (reviewId !== undefined) {
                  dismissReview({reviewId, message: dismissalMessage})
                } else {
                  alert('Review ID is undefined')
                }
              }}
            >
              Dismiss
            </Button>
          </Dialog.Footer>
        </Dialog>
      )}
    </ListItem>
  )
}

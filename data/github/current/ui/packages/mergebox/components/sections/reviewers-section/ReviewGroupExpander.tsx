import {useAnalytics} from '@github-ui/use-analytics'
import {Button} from '@primer/react'
import {type PropsWithChildren, useId} from 'react'
import {CheckIcon, FileDiffIcon, PersonIcon} from '@primer/octicons-react'
import styles from './ReviewGroupExpander.module.css'
import {useSessionStorage} from '@github-ui/use-safe-storage/session-storage'
import {clsx} from 'clsx'
import {ExpandableGroupIcon} from '../common/ExpandableGroupIcon'
import {ReviewGroup} from '../../../types'

type ReviewGroupIconMap = Record<ReviewGroup, JSX.Element>

const reviewGroupIconMap: ReviewGroupIconMap = {
  [ReviewGroup.Approvals]: <CheckIcon className="fgColor-success" size={16} />,
  [ReviewGroup.RequestedChanges]: <FileDiffIcon className="fgColor-danger" size={16} />,
  [ReviewGroup.PendingReviewRequest]: <PersonIcon size={16} />,
}

function singularReviewGroupString(reviewGroup: ReviewGroup) {
  return reviewGroup.substring(0, reviewGroup.length - 1)
}

export function ReviewGroupExpander({
  children,
  count,
  pullRequestId,
  reviewGroup,
}: PropsWithChildren<{
  count: number
  pullRequestId: string
  reviewGroup: ReviewGroup
}>) {
  const {sendAnalyticsEvent} = useAnalytics()
  const [isExpanded, setIsExpanded] = useSessionStorage<boolean>(
    `${pullRequestId}:reviewersGroup:${reviewGroup}Expanded`,
    false,
  )
  const groupContentId = useId()
  const reviewGroupIcon = reviewGroupIconMap[reviewGroup]
  const reviewGroupWithCount = `${count} ${count > 1 ? reviewGroup : singularReviewGroupString(reviewGroup)}`

  return (
    <>
      <Button
        aria-controls={groupContentId}
        aria-expanded={isExpanded}
        aria-label={isExpanded ? `Collapse ${reviewGroupWithCount} group` : `Expand ${reviewGroupWithCount} group`}
        className={styles.groupHeadingButton}
        variant="invisible"
        size="small"
        trailingVisual={() => <ExpandableGroupIcon isExpanded={isExpanded} />}
        onClick={() => {
          const eventTarget = 'MERGEBOX_REVIEWERS_GROUP_TOGGLE_BUTTON'
          const eventType = isExpanded ? 'reviewers_group.collapse' : 'reviewers_group.expand'
          const eventMetadata = {group: reviewGroup}
          sendAnalyticsEvent(eventType, eventTarget, eventMetadata)
          setIsExpanded(!isExpanded)
        }}
      >
        {reviewGroupIcon} <span className="ml-1">{reviewGroupWithCount}</span>
      </Button>
      <div
        className={clsx(styles.expandableWrapper, isExpanded && styles.isExpanded)}
        id={groupContentId}
        aria-label={reviewGroupWithCount}
        role="group"
      >
        <div className={styles.expandableListView}>{isExpanded && children}</div>
      </div>
    </>
  )
}

import {MarkdownViewer} from '@github-ui/markdown-viewer'
import {ChevronDownIcon, ChevronUpIcon} from '@primer/octicons-react'
import {StateLabel, RelativeTime, ProgressBar, Button} from '@primer/react'
import {useFragment} from 'react-relay'
import {graphql} from 'relay-runtime'
import {LABELS} from './constants/labels'
import styles from './RepositoryMilestone.module.css'
import {useState} from 'react'
import type {MilestoneDetail$key} from './__generated__/MilestoneDetail.graphql'
import {clsx} from 'clsx'
import type {SafeHTMLString} from '@github-ui/safe-html'
import {MilestoneDate} from './MilestoneDate'

type MilestoneDetailProps = {
  milestoneRef: MilestoneDetail$key
}

export function MilestoneDetail({milestoneRef}: MilestoneDetailProps) {
  const currentMilestone = useFragment(
    graphql`
      fragment MilestoneDetail on Milestone {
        closed
        updatedAt
        description
        descriptionHTML
        progressPercentage
        ...MilestoneDate
      }
    `,
    milestoneRef,
  )

  const [isShowMore, setIsShowMore] = useState(false)

  const descriptionExceedsLimit = currentMilestone.descriptionHTML && currentMilestone.descriptionHTML.length > 600

  const showMoreLessClass = () => {
    if (descriptionExceedsLimit) {
      return isShowMore ? styles.expanded : styles.collapsed
    } else {
      return null
    }
  }

  return (
    <div
      className={`${styles.milestoneDetailsWrapper} ${isShowMore && descriptionExceedsLimit ? styles.expanded : ''}`}
    >
      <div className={styles.metadataWrapper}>
        <div className={styles.status} data-testid="milestone-status">
          <StateLabel
            className={styles.milestoneStatus}
            variant="small"
            status={currentMilestone.closed ? 'closed' : 'open'}
          >
            {currentMilestone.closed ? LABELS.milestoneClosed : LABELS.milestoneOpen}
          </StateLabel>
          <div className={styles.milestoneDataContainer}>
            <MilestoneDate milestone={currentMilestone} />
            <span>
              {currentMilestone.closed ? <>{LABELS.milestoneClosed}</> : <>{LABELS.milestoneLastUpdated}</>}
              <RelativeTime date={new Date(currentMilestone.updatedAt)} tense="past" />
            </span>
          </div>
        </div>
        <div className={styles.progressSection}>
          <span>
            <span className={styles.progressPercentage}>{Math.floor(currentMilestone.progressPercentage)}%</span>{' '}
            complete
          </span>
          <ProgressBar progress={Math.floor(currentMilestone.progressPercentage)} aria-hidden="true" />
        </div>
      </div>
      {currentMilestone.description && currentMilestone.descriptionHTML ? (
        <div className={styles.milestoneDescription} id="milestone-description">
          <MarkdownViewer
            className={clsx(styles.mdViewer, showMoreLessClass())}
            markdownValue={currentMilestone.description}
            verifiedHTML={currentMilestone.descriptionHTML as SafeHTMLString}
            onChange={() => {}}
          />
          {descriptionExceedsLimit && (
            <div className={clsx(styles.showMoreButtonContainer, isShowMore ? styles.expanded : styles.collapsed)}>
              <Button
                size="small"
                variant="invisible"
                className={styles.button}
                onClick={() => {
                  setIsShowMore(!isShowMore)
                }}
                aria-expanded={isShowMore}
                aria-controls="milestone-description"
                trailingVisual={isShowMore ? ChevronUpIcon : ChevronDownIcon}
              >
                {isShowMore ? 'Show less' : 'Show more'}
              </Button>
            </div>
          )}
        </div>
      ) : null}
    </div>
  )
}

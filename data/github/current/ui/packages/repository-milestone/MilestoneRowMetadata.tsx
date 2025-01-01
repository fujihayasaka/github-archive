import {useFragment} from 'react-relay'
import {graphql} from 'relay-runtime'
import type {MilestoneRowMetadata$key} from './__generated__/MilestoneRowMetadata.graphql'
import styles from './RepositoryMilestone.module.css'
import {Link, ProgressBar} from '@primer/react'
import {MilestoneRowMenu} from './MilestoneRowMenu'

type MilestoneRowMetadataProps = {
  milestone: MilestoneRowMetadata$key
  repositoryNameWithOwner: string
}

export function MilestoneRowMetadata({milestone, repositoryNameWithOwner}: MilestoneRowMetadataProps) {
  const data = useFragment(
    graphql`
      fragment MilestoneRowMetadata on Milestone {
        ...MilestoneRowMenu
        progressPercentage
        openIssueCount
        closedIssueCount
        title
      }
    `,
    milestone,
  )

  const getLinkUrl = (state: string) =>
    `/${repositoryNameWithOwner}/issues?q=${encodeURIComponent(`is:${state} milestone:"${data.title ?? ''}"`)}`

  return (
    <div className={styles.listProgressSection}>
      <div className={styles.progress}>
        <ProgressBar
          progress={Math.floor(data.progressPercentage)}
          aria-hidden="true"
          data-testid="milestone-metadata-progress-bar"
          barSize="small"
          className={styles.progressBar}
        />
        <div className={styles.listMetadata}>
          <span>
            <span className={styles.progressPercentage}>{Math.floor(data.progressPercentage)}%</span> complete
          </span>
          <Link className={styles.link} href={getLinkUrl('open')}>
            <span className={styles.progressPercentage}>{data.openIssueCount}</span> open
          </Link>
          <Link className={styles.link} href={getLinkUrl('closed')}>
            <span className={styles.progressPercentage}>{data.closedIssueCount}</span> closed
          </Link>
        </div>
      </div>
      <MilestoneRowMenu milestone={data} />
    </div>
  )
}

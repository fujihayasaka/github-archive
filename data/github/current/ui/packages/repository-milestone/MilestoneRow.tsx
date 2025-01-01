import {useFragment} from 'react-relay'
import {graphql} from 'relay-runtime'
import type {MilestoneRow$key} from './__generated__/MilestoneRow.graphql'
import {ListItem} from '@github-ui/list-view/ListItem'
import {ListItemMainContent} from '@github-ui/list-view/ListItemMainContent'
import {ListItemDescription} from '@github-ui/list-view/ListItemDescription'
import {MilestoneDate} from './MilestoneDate'
import {MilestoneRowTitle} from './MilestoneRowTitle'
import {MilestoneRowMetadata} from './MilestoneRowMetadata'
import {MilestoneIssueCount} from './MilestoneIssueCount'
import styles from './RepositoryMilestone.module.css'

type MilestoneRowProps = {
  milestone: MilestoneRow$key
  repositoryNameWithOwner: string
}

export function MilestoneRow({milestone, repositoryNameWithOwner}: MilestoneRowProps) {
  const data = useFragment(
    graphql`
      fragment MilestoneRow on Milestone {
        description
        id
        ...MilestoneRowTitle
        ...MilestoneRowMetadata
        ...MilestoneDate
        ...MilestoneIssueCount
      }
    `,
    milestone,
  )

  const title = <MilestoneRowTitle milestone={data} />
  const metadata = <MilestoneRowMetadata milestone={data} repositoryNameWithOwner={repositoryNameWithOwner} />

  return (
    <ListItem
      key={data.id}
      title={title}
      role="listitem"
      metadata={metadata}
      className={styles.milestoneRow}
      metadataContainerClassName={styles.listMetadataContainer}
    >
      <ListItemMainContent>
        <ListItemDescription className={styles.listItemContent}>
          {data.description && <p className={styles.listDescription}>{data.description}</p>}
          <div className={styles.listDateContainer}>
            <MilestoneDate milestone={data} />
            <MilestoneIssueCount milestone={data} />
          </div>
        </ListItemDescription>
      </ListItemMainContent>
    </ListItem>
  )
}

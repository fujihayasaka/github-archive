import {Breadcrumbs, Heading} from '@primer/react'
import {useFragment} from 'react-relay'
import {graphql} from 'relay-runtime'
import type {MilestoneTitle$key} from './__generated__/MilestoneTitle.graphql'
import styles from './RepositoryMilestone.module.css'

type MilestoneTitleProps = {
  milestoneRef: MilestoneTitle$key
}

export function MilestoneTitle({milestoneRef}: MilestoneTitleProps) {
  const {title, repository} = useFragment(
    graphql`
      fragment MilestoneTitle on Milestone {
        title
        repository {
          nameWithOwner
        }
      }
    `,
    milestoneRef,
  )

  return (
    <div className={styles.milestoneTitleWrapper}>
      <Breadcrumbs>
        <Breadcrumbs.Item href={`/${repository.nameWithOwner}/milestones`}>Milestones</Breadcrumbs.Item>
        <Breadcrumbs.Item selected>
          <span>{title.length > 30 ? `${title.slice(0, 30)}…` : title}</span>
        </Breadcrumbs.Item>
      </Breadcrumbs>
      <Heading className={styles.title} as="h2">
        {title}
      </Heading>
    </div>
  )
}

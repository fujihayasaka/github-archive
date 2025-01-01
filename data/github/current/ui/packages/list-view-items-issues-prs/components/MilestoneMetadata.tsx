import {graphql} from 'relay-runtime'
import type {MilestoneMetadata$key} from './__generated__/MilestoneMetadata.graphql'
import {useFragment} from 'react-relay'
import {Link, Truncate} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {MilestoneIcon} from '@primer/octicons-react'

const milestoneFragment = graphql`
  fragment MilestoneMetadata on IssueOrPullRequest
  @argumentDefinitions(includeMilestone: {type: "Boolean!", defaultValue: true}) {
    ... on Issue {
      milestone @include(if: $includeMilestone) {
        title
        url
      }
    }

    ... on PullRequest {
      milestone @include(if: $includeMilestone) {
        title
        url
      }
    }
  }
`

type MilestoneMetadataProps = {
  data: MilestoneMetadata$key
}

export const MilestoneMetadata = ({data}: MilestoneMetadataProps) => {
  const {milestone} = useFragment(milestoneFragment, data)

  if (!milestone) return null

  return (
    <>
      &nbsp;&middot;&nbsp;
      <Link
        href={milestone.url}
        muted
        aria-label={milestone.title}
        sx={{display: 'inline-flex', verticalAlign: 'bottom'}}
      >
        <Octicon icon={MilestoneIcon} size={16} />
        &nbsp;
        <Truncate
          title={milestone.title}
          sx={{
            display: 'inline-block',
            maxWidth: '100px',
            verticalAlign: 'bottom',
          }}
        >
          {milestone.title}
        </Truncate>
      </Link>
    </>
  )
}

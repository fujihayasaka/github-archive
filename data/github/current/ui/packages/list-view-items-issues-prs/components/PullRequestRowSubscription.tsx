import {useMemo} from 'react'
import {graphql, useSubscription} from 'react-relay'

import type {PullRequestRowSubscription} from './__generated__/PullRequestRowSubscription.graphql'

const subscription = graphql`
  subscription PullRequestRowSubscription($pullRequestId: ID!) {
    pullRequestInfoForListViewUpdated(id: $pullRequestId) {
      titleUpdated {
        title
        titleHTML
      }
      statusUpdated {
        state
        isDraft
      }
      commentsUpdated {
        ...PullRequestItemMetadata
      }
      reviewDecisionUpdated {
        ...IssuePullRequestDescription
      }
      commitChecksUpdated {
        ...CheckRunStatusFromPullRequest
      }
    }
  }
`

export const usePullRequestRowSubscription = (pullRequestId: string) => {
  const config = useMemo(() => {
    return {
      subscription,
      variables: {pullRequestId},
    }
  }, [pullRequestId])

  useSubscription<PullRequestRowSubscription>(config)
}

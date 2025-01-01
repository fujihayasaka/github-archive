import {graphql, useFragment, usePreloadedQuery, type PreloadedQuery} from 'react-relay'
import type {IssueRowSecondaryQuery} from './__generated__/IssueRowSecondaryQuery.graphql'
import {IssuesIndexSecondaryGraphqlQuery} from './IssueRow'
import {Suspense} from 'react'
import type {IssueOrPullRequestUnreadIndicator$key} from './__generated__/IssueOrPullRequestUnreadIndicator.graphql'
import {UnreadIndicator} from './UnreadIndicator'

const notificationFragment = graphql`
  fragment IssueOrPullRequestUnreadIndicator on IssueOrPullRequest {
    __typename
    ... on Issue {
      isReadByViewer
    }
    ... on PullRequest {
      isReadByViewer
    }
  }
`

type IssueOrPullRequestUnreadIndicatorProps = {
  issueId: string
  metadataRef?: PreloadedQuery<IssueRowSecondaryQuery> | null
}

export function IssueOrPullRequestUnreadIndicator({issueId, metadataRef}: IssueOrPullRequestUnreadIndicatorProps) {
  if (!metadataRef) return null

  return (
    <Suspense fallback={null}>
      <IssueOrPullRequestUnreadIndicatorFetched issueId={issueId} metadataRef={metadataRef} />
    </Suspense>
  )
}

type IssueOrPullRequestUnreadIndicatorFetchedProps = {
  issueId: string
  metadataRef: PreloadedQuery<IssueRowSecondaryQuery>
}

function IssueOrPullRequestUnreadIndicatorFetched({
  issueId,
  metadataRef,
}: IssueOrPullRequestUnreadIndicatorFetchedProps) {
  const {nodes} = usePreloadedQuery<IssueRowSecondaryQuery>(IssuesIndexSecondaryGraphqlQuery, metadataRef)
  const issueNode = nodes?.find(node => node?.id === issueId)

  if (!issueNode) return null

  return <IssueOrPullRequestUnreadIndicatorInternal notificationKey={issueNode} />
}

type IssueOrPullRequestUnreadIndicatorInternalProps = {
  notificationKey?: IssueOrPullRequestUnreadIndicator$key
}

function IssueOrPullRequestUnreadIndicatorInternal({notificationKey}: IssueOrPullRequestUnreadIndicatorInternalProps) {
  const data = useFragment(notificationFragment, notificationKey)

  const isReadByViewer = data && 'isReadByViewer' in data ? data.isReadByViewer : false

  return <UnreadIndicator unread={!isReadByViewer} />
}

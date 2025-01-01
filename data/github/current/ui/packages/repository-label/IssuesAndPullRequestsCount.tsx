import {ListItemDescriptionItem} from '@github-ui/list-view/ListItemDescriptionItem'
import {GitPullRequestIcon, IssueOpenedIcon, AlertIcon} from '@primer/octicons-react'
import {Link, SkeletonBox, Tooltip, VisuallyHidden} from '@primer/react'
import {graphql, useFragment, usePreloadedQuery, type PreloadedQuery} from 'react-relay'
import styles from './RepositoryLabel.module.css'
import {Suspense, useCallback} from 'react'
import type {IssuesAndPullRequestsCount$key} from './__generated__/IssuesAndPullRequestsCount.graphql'
import type {IssuesAndPullRequestsCountSecondaryQuery} from './__generated__/IssuesAndPullRequestsCountSecondaryQuery.graphql'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {clsx} from 'clsx'

type IssuesAndPullRequestsCount = {
  secondaryQueryRef?: PreloadedQuery<IssuesAndPullRequestsCountSecondaryQuery> | null
  labelName: string
  labelId: string
  repositoryNameWithOwner: string
}

export const IssuesAndPullRequestsCountSecondaryQueryQ = graphql`
  query IssuesAndPullRequestsCountSecondaryQuery($nodes: [ID!]!) {
    nodes(ids: $nodes) {
      id
      ... on Label {
        ...IssuesAndPullRequestsCount
      }
    }
  }
`

export const IssuesAndPullRequestsCount = ({
  secondaryQueryRef,
  labelName,
  labelId,
  repositoryNameWithOwner,
}: IssuesAndPullRequestsCount) => {
  if (!secondaryQueryRef) return null

  return (
    <ErrorBoundary
      fallback={
        <ListItemDescriptionItem className={styles.labelRowIssuesAndPrsCount}>
          <AlertIcon size={16} /> Could not load data
        </ListItemDescriptionItem>
      }
    >
      <Suspense fallback={<LoadingLabelSecondaryData />}>
        <IssuesAndPullRequestsCountFetched
          labelName={labelName}
          labelId={labelId}
          secondaryQueryRef={secondaryQueryRef}
          repositoryNameWithOwner={repositoryNameWithOwner}
        />
      </Suspense>
    </ErrorBoundary>
  )
}

const LoadingLabelSecondaryData = () => {
  return (
    <ListItemDescriptionItem className={styles.labelRowIssuesAndPrsCount}>
      <SkeletonBox className={styles.loadingIssueAndPullRequestCount} />
      <SkeletonBox className={styles.loadingIssueAndPullRequestCount} />
    </ListItemDescriptionItem>
  )
}

export const IssuesAndPullRequestsCountFetched = ({
  secondaryQueryRef,
  labelName,
  labelId,
  repositoryNameWithOwner,
}: IssuesAndPullRequestsCount & {secondaryQueryRef: PreloadedQuery<IssuesAndPullRequestsCountSecondaryQuery>}) => {
  const {nodes} = usePreloadedQuery<IssuesAndPullRequestsCountSecondaryQuery>(
    IssuesAndPullRequestsCountSecondaryQueryQ,
    secondaryQueryRef,
  )

  const labelNode = nodes?.find(node => node?.id === labelId)

  if (!labelNode) return null

  return (
    <IssuesAndPullRequestsCountInternal
      repositoryNameWithOwner={repositoryNameWithOwner}
      labelName={labelName}
      labelNode={labelNode}
    />
  )
}

export const IssuesAndPullRequestsCountInternal = ({
  labelName,
  labelNode,
  repositoryNameWithOwner,
}: {
  labelName: string
  labelNode: IssuesAndPullRequestsCount$key
  repositoryNameWithOwner: string
}) => {
  const data = useFragment(
    graphql`
      fragment IssuesAndPullRequestsCount on Label {
        issueCount
        pullRequestCount
      }
    `,
    labelNode,
  )

  const getLink = useCallback(
    (type: 'issue' | 'pr') => {
      const query = `${encodeURIComponent(`is:open is:${type} label:"${labelName}"`)}`
      return `/${repositoryNameWithOwner}/issues?q=${query}`
    },
    [repositoryNameWithOwner, labelName],
  )

  const openIssues = data.issueCount || 0
  const openPullRequests = data.pullRequestCount || 0

  const hasPullRequest = openPullRequests > 0
  const hasIssues = openIssues > 0

  return (
    <ListItemDescriptionItem className={styles.labelRowIssuesAndPrsCount}>
      <div className={clsx(styles.countContainer, !hasPullRequest && styles.empty)}>
        {hasPullRequest && (
          <Tooltip text={`${openPullRequests} open pull requests`} direction="n">
            <Link href={getLink('pr')} muted className={styles.countItem}>
              <GitPullRequestIcon size={16} />
              {openPullRequests} <VisuallyHidden>open pull requests</VisuallyHidden>
            </Link>
          </Tooltip>
        )}
      </div>
      <div className={clsx(styles.countContainer, !hasIssues && styles.empty)}>
        {hasIssues && (
          <Tooltip text={`${openIssues} open issues`} direction="n">
            <Link href={getLink('issue')} muted className={styles.countItem}>
              <IssueOpenedIcon size={16} />
              {openIssues} <VisuallyHidden>open issues</VisuallyHidden>
            </Link>
          </Tooltip>
        )}
      </div>
    </ListItemDescriptionItem>
  )
}

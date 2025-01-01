import {ListItemDescription} from '@github-ui/list-view/ListItemDescription'
import {ListItemLeadingContent} from '@github-ui/list-view/ListItemLeadingContent'
import {ListItemMainContent} from '@github-ui/list-view/ListItemMainContent'
import {ListItem} from '@github-ui/list-view/ListItem'
import {noop} from '@github-ui/noop'
import {graphql, useFragment, type PreloadedQuery} from 'react-relay'
import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'

import type {PullRequestItem$key} from './__generated__/PullRequestItem.graphql'
import {LazyPullRequestItemMetadata, type PullRequestItemMetadataProps} from './PullRequestItemMetadata'
import {IssuePullRequestDescription} from './IssuePullRequestDescription'
import {IssuePullRequestStateIcon} from './IssuePullRequestStateIcon'
import {IssuePullRequestTitle} from './IssuePullRequestTitle'
import {QUERY_FIELDS} from '../constants/queries'
import type {CommonItemProps} from '../constants/types'
import type {IssueRowSecondaryQuery} from './__generated__/IssueRowSecondaryQuery.graphql'
import {IssueOrPullRequestUnreadIndicator} from './IssueOrPullRequestUnreadIndicator'
import type {PullRequestItemHeadCommit$key} from './__generated__/PullRequestItemHeadCommit.graphql'
import {CheckRunStatusFragment} from './CheckRunStatus'
import type {CheckRunStatus$key} from './__generated__/CheckRunStatus.graphql'

import styles from './PullRequestItem.module.css'
import {getIssueTitle} from '@github-ui/issue-viewer/Helpers'

export const PullRequestItemHeadCommitFragment = graphql`
  fragment PullRequestItemHeadCommit on PullRequest {
    headCommit {
      commit {
        id
        ...CheckRunStatus
      }
    }
  }
`

// This component represents a single 'basic' pull request displayed in the list
// It styles a given pull request using the ListItem component

export const PullRequestItemQuery = graphql`
  fragment PullRequestItem on PullRequest
  @argumentDefinitions(
    labelPageSize: {type: "Int!", defaultValue: 10}
    includeGitData: {type: "Boolean!", defaultValue: true}
    includeMilestone: {type: "Boolean!", defaultValue: true}
  ) {
    id
    __typename
    ...PullRequestItemHeadCommit @dangerously_unaliased_fixme @include(if: $includeGitData)
    ...CheckRunStatusFromPullRequest @dangerously_unaliased_fixme @include(if: $includeGitData)
    repository {
      name
      owner {
        login
      }
    }
    title
    titleHTML
    ...IssuePullRequestTitle @arguments(labelPageSize: $labelPageSize)
    ...IssuePullRequestDescription @arguments(includeGitData: $includeGitData, includeMilestone: $includeMilestone)
    ...IssuePullRequestStateIcon @arguments(includeGitData: $includeGitData)
  }
`

export type PullRequestItemProps = {
  itemKey: PullRequestItem$key
  metadataRef?: PreloadedQuery<IssueRowSecondaryQuery> | null
  showLeadingRightSideContent?: boolean
  showRepository?: boolean
  sortingItemSelected?: string
  includeReactions?: boolean
  includeGitDataFromMainQuery?: boolean
  as?: React.ElementType
  role?: string
} & Omit<PullRequestItemMetadataProps, 'itemKey'>

export const PullRequestItem = ({
  itemKey,
  metadataRef,
  isActive = false,
  isSelected,
  ref,
  href,
  showCommentCount,
  showCommentZeroCount,
  showAssignees,
  showRepository = true,
  onSelect = noop,
  onClick = noop,
  getMetadataHref,
  reactionEmojiToDisplay,
  sortingItemSelected,
  includeGitDataFromMainQuery,
  as,
  role,
}: PullRequestItemProps & CommonItemProps) => {
  const data = useFragment(PullRequestItemQuery, itemKey)
  const titleValue = data && getIssueTitle(data.title, data.titleHTML)
  const {pull_request_single_subscription} = useFeatureFlags()

  const headCommitData = useFragment<PullRequestItemHeadCommit$key>(
    PullRequestItemHeadCommitFragment,
    !pull_request_single_subscription && includeGitDataFromMainQuery ? data : null,
  )
  const statusCheckRollupData = useFragment<CheckRunStatus$key>(
    CheckRunStatusFragment,
    !pull_request_single_subscription ? headCommitData?.headCommit?.commit : null,
  )

  const title = (
    <IssuePullRequestTitle
      value={titleValue}
      dataKey={data}
      href={href}
      ref={ref}
      repositoryOwner={data.repository.owner.login}
      repositoryName={data.repository.name}
      onClick={onClick}
      getLabelHref={label => getMetadataHref(QUERY_FIELDS.label, label)}
    />
  )
  const description = (
    <IssuePullRequestDescription
      repositoryOwner={data.repository.owner.login}
      repositoryName={data.repository.name}
      statusCheckRollup={statusCheckRollupData?.statusCheckRollup || undefined}
      dataKey={data}
      showRepository={showRepository}
      sortingItemSelected={sortingItemSelected}
      getAuthorHref={(login: string) => getMetadataHref('author', login)}
      id={data.id}
      metadataRef={metadataRef}
      includeGitDataFromMainQuery={includeGitDataFromMainQuery}
    />
  )

  const lazyMetadata = (
    <LazyPullRequestItemMetadata
      pullId={data.id}
      metadataRef={metadataRef}
      getMetadataHref={getMetadataHref}
      reactionEmojiToDisplay={reactionEmojiToDisplay}
      showAssignees={showAssignees}
      showCommentCount={showCommentCount}
      showCommentZeroCount={showCommentZeroCount}
    />
  )
  return (
    <ListItem
      key={data.id}
      title={title}
      isActive={isActive}
      isSelected={isSelected}
      onSelect={onSelect}
      metadata={lazyMetadata}
      metadataContainerClassName={styles.ListItem_0}
      role={role || 'listitem'}
      as={as}
    >
      <IssueOrPullRequestUnreadIndicator metadataRef={metadataRef} issueId={data.id} />
      <ListItemLeadingContent>
        <IssuePullRequestStateIcon id={data.id} dataKey={data} metadataRef={metadataRef} />
      </ListItemLeadingContent>
      <ListItemMainContent>
        <ListItemDescription>{description}</ListItemDescription>
      </ListItemMainContent>
    </ListItem>
  )
}

PullRequestItem.nodeType = 'pullRequest'

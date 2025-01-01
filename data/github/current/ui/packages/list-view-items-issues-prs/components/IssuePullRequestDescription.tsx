import {GitHubAvatar} from '@github-ui/github-avatar'
import {ListItemDescriptionItem} from '@github-ui/list-view/ListItemDescriptionItem'
import {useListViewVariant} from '@github-ui/list-view/ListViewVariantContext'
import {Link, RelativeTime, Truncate} from '@primer/react'
import {graphql, useFragment, type PreloadedQuery} from 'react-relay'

import {LABELS} from '../constants/labels'
import {TEST_IDS} from '../constants/test-ids'
import type {IssuePullRequestDescription$key} from './__generated__/IssuePullRequestDescription.graphql'
import {LazyReviewDecision, ReviewDecision} from './ReviewDecision'
import {userHovercardPath} from '@github-ui/paths'
import styles from './issue-item.module.css'
import {VALUES} from '../constants/values'
import {MilestoneMetadata} from './MilestoneMetadata'
import type {IssueRowSecondaryQuery} from './__generated__/IssueRowSecondaryQuery.graphql'
import {CheckRunStatus, LazyCheckRunStatus} from './CheckRunStatus'
import type {CheckRunStatus$data} from './__generated__/CheckRunStatus.graphql'
import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'
import type {CheckRunStatusFromPullRequest$key} from './__generated__/CheckRunStatusFromPullRequest.graphql'

const descriptionFragment = graphql`
  fragment IssuePullRequestDescription on IssueOrPullRequest
  @argumentDefinitions(includeGitData: {type: "Boolean", defaultValue: true}) {
    ... on Issue {
      createdAt
      updatedAt
      closed
      closedAt

      author {
        login
        avatarUrl
      }
      number
      stateReason(enableDuplicate: true)
      ...MilestoneMetadata
    }

    ... on PullRequest {
      createdAt
      updatedAt
      closed
      closedAt
      author {
        login
        avatarUrl
      }
      number
      ...MilestoneMetadata
      reviewDecision @include(if: $includeGitData)
    }
  }
`

type DescriptionProps = {
  dataKey: IssuePullRequestDescription$key | CheckRunStatusFromPullRequest$key
  metadataRef?: PreloadedQuery<IssueRowSecondaryQuery> | null
  repositoryOwner: string
  repositoryName: string
  showRepository?: boolean
  showAuthorAvatar?: boolean
  showTimestamp?: boolean
  sortingItemSelected?: string
  statusCheckRollup?: NonNullable<CheckRunStatus$data['statusCheckRollup']>
  getAuthorHref?: (login: string) => string
  id: string
  includeGitDataFromMainQuery?: boolean
}

export function IssuePullRequestDescription({dataKey, repositoryOwner, repositoryName, ...props}: DescriptionProps) {
  const {number} = useFragment(descriptionFragment, dataKey as IssuePullRequestDescription$key)
  const nameWithOwner = `${repositoryOwner}/${repositoryName}`
  const ariaLabels: {[id: string]: string} = {
    number: `number ${number} `,
    repo: `In ${nameWithOwner};`,
  }

  const defaultRepositoryRender = (
    <div className={styles.defaultRepoContainer}>
      <span>{props.showRepository ? nameWithOwner : ''}</span>
      <span className="sr-only">{ariaLabels.number}</span>
    </div>
  )

  const defaultMetaRender = (
    <span className={styles.defaultNumberDescription}>
      <span>#{number}</span>
      &nbsp;
      <span className="sr-only">{ariaLabels.repo}</span>
    </span>
  )

  return (
    <IssuePullRequestDescriptionItem
      dataKey={dataKey}
      defaultRepositoryRender={defaultRepositoryRender}
      defaultMetaRender={defaultMetaRender}
      nameWithOwner={nameWithOwner}
      repositoryOwner={repositoryOwner}
      repositoryName={repositoryName}
      ariaLabels={ariaLabels}
      {...props}
    />
  )
}

const IssuePullRequestDescriptionItem = ({
  dataKey,
  metadataRef,
  showRepository = true,
  showAuthorAvatar = false,
  showTimestamp = true,
  sortingItemSelected,
  statusCheckRollup,
  defaultRepositoryRender,
  defaultMetaRender,
  nameWithOwner,
  ariaLabels,
  getAuthorHref,
  id,
  includeGitDataFromMainQuery,
}: DescriptionProps & {
  defaultRepositoryRender: React.ReactNode
  defaultMetaRender: React.ReactNode
  nameWithOwner: string
  ariaLabels: {[id: string]: string}
}) => {
  const descriptionData = useFragment(descriptionFragment, dataKey as IssuePullRequestDescription$key)
  const {issues_react_close_as_duplicate, pull_request_single_subscription} = useFeatureFlags()

  const {variant} = useListViewVariant()

  const {
    author,
    reviewDecision,
    closed,
    closedAt: closedAtString,
    createdAt: createdAtString,
    updatedAt: updatedAtString,
    stateReason,
  } = descriptionData

  const authorLogin = author?.login || VALUES.ghostUserLogin
  const authorAvatarUrl = author?.avatarUrl || VALUES.ghostUserAvatarUrl
  const createdAt = createdAtString ? new Date(createdAtString) : undefined
  const updatedAt = updatedAtString ? new Date(updatedAtString) : undefined
  const closedAt = closedAtString ? new Date(closedAtString) : undefined
  const loadStatusCheckFromMainQuery = pull_request_single_subscription && includeGitDataFromMainQuery
  return (
    <ListItemDescriptionItem data-testid={TEST_IDS.listRowRepoNameAndNumber}>
      {variant === 'compact'
        ? showRepository && (
            <>
              <Truncate
                title={nameWithOwner}
                sx={{color: 'fg.muted', fontWeight: 'normal', fontSize: 0, maxWidth: 300}}
              >
                <span className={styles.compactNameWithOwnerLabel}>{nameWithOwner}</span>
              </Truncate>
              <span className="sr-only">{ariaLabels.number}</span>
            </>
          )
        : showRepository && defaultRepositoryRender}
      {defaultMetaRender}
      {showTimestamp && variant === 'default' && (
        <>
          {closed ? (
            <TimestampContainer
              showAuthorAvatar={showAuthorAvatar}
              authorAvatarUrl={authorAvatarUrl}
              authorLogin={authorLogin}
              getAuthorHref={getAuthorHref}
              hovercardPath={userHovercardPath}
              timestamp={closedAt}
              testId="closed-at"
              action={ActionType.Closed}
            />
          ) : (
            <TimestampContainer
              showAuthorAvatar={showAuthorAvatar}
              authorAvatarUrl={authorAvatarUrl}
              authorLogin={authorLogin}
              getAuthorHref={getAuthorHref}
              hovercardPath={userHovercardPath}
              timestamp={createdAt}
              testId="created-at"
              action={ActionType.Opened}
            />
          )}
          {(sortingItemSelected === LABELS.RecentlyUpdated || sortingItemSelected === 'updated') && updatedAt && (
            <div data-testid="updated-at" className={styles.timestampContainer}>
              &middot; Updated{' '}
              <RelativeTime date={updatedAt} sx={{verticalAlign: 'bottom'}}>
                on {updatedAt.toLocaleDateString('en-US', {month: 'short', day: 'numeric', year: 'numeric'})}
              </RelativeTime>
            </div>
          )}
        </>
      )}
      {issues_react_close_as_duplicate && stateReason?.toLowerCase() === 'duplicate' && (
        <span data-testid="state-reason"> &middot;{' Duplicate'}</span>
      )}
      {reviewDecision ? (
        <ReviewDecision decision={reviewDecision} variant={variant} />
      ) : (
        <LazyReviewDecision id={id} variant={variant} secondaryQueryRef={metadataRef} />
      )}
      <MilestoneMetadata data={descriptionData} />
      {statusCheckRollup ? (
        <CheckRunStatus variant={variant} statusCheckRollup={statusCheckRollup} />
      ) : (
        <LazyCheckRunStatus
          id={id}
          variant={variant}
          primaryQueryRef={loadStatusCheckFromMainQuery ? (dataKey as CheckRunStatusFromPullRequest$key) : undefined}
          secondaryQueryRef={metadataRef}
        />
      )}
    </ListItemDescriptionItem>
  )
}

enum ActionType {
  Opened = 'opened',
  Closed = 'closed',
}

const TimestampContainer = ({
  showAuthorAvatar,
  authorAvatarUrl,
  authorLogin,
  getAuthorHref,
  hovercardPath,
  timestamp,
  testId,
  action,
}: {
  showAuthorAvatar: boolean
  authorAvatarUrl: string
  authorLogin: string
  getAuthorHref?: (login: string) => string
  hovercardPath: (params: {owner: string}) => string
  timestamp?: Date
  testId: string
  action: ActionType
}) => (
  <div data-testid={testId} className={styles.timestampContainer}>
    &middot; {action === ActionType.Closed && ' by '}
    {showAuthorAvatar && authorAvatarUrl && (
      <GitHubAvatar src={authorAvatarUrl} size={16} alt={authorLogin} sx={{mr: 1}} />
    )}
    <Link
      href={getAuthorHref ? getAuthorHref(authorLogin) : `/${authorLogin}`}
      aria-label={`Add author ${authorLogin} to current search query`}
      className={styles.authorCreatedLink}
      data-hovercard-url={hovercardPath({owner: authorLogin})}
    >
      {authorLogin}
    </Link>{' '}
    {action === ActionType.Opened ? ` opened ` : ` was closed `}
    {timestamp && (
      <RelativeTime date={timestamp}>
        on {timestamp.toLocaleDateString('en-US', {month: 'short', day: 'numeric', year: 'numeric'})}
      </RelativeTime>
    )}
  </div>
)

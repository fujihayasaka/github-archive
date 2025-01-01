import {ListItemDescriptionItem} from '@github-ui/list-view/ListItemDescriptionItem'
import {useListViewVariant} from '@github-ui/list-view/ListViewVariantContext'
import {Link, RelativeTime, Truncate} from '@primer/react'
import {graphql, useFragment, type PreloadedQuery} from 'react-relay'

import {LABELS} from '../constants/labels'
import {TEST_IDS} from '../constants/test-ids'
import type {IssuePullRequestDescription$key} from './__generated__/IssuePullRequestDescription.graphql'
import {LazyReviewDecision, ReviewDecision} from './ReviewDecision'
import styles from './IssueItem.module.css'
import {VALUES} from '../constants/values'
import {MilestoneMetadata} from './MilestoneMetadata'
import type {IssueRowSecondaryQuery} from './__generated__/IssueRowSecondaryQuery.graphql'
import {CheckRunStatus, LazyCheckRunStatus} from './CheckRunStatus'
import type {CheckRunStatus$data} from './__generated__/CheckRunStatus.graphql'
import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'
import type {CheckRunStatusFromPullRequest$key} from './__generated__/CheckRunStatusFromPullRequest.graphql'
import {hovercardAttributesForActor, type HovercardAttributes} from '@github-ui/hovercards'

const descriptionFragment = graphql`
  fragment IssuePullRequestDescription on IssueOrPullRequest
  @argumentDefinitions(
    includeGitData: {type: "Boolean", defaultValue: true}
    includeMilestone: {type: "Boolean!", defaultValue: true}
  ) {
    ... on Issue {
      createdAt
      updatedAt
      closed
      closedAt

      author {
        login
        resourcePath
        __typename
        ... on Bot {
          isCopilot
        }
      }
      number
      stateReason(enableDuplicate: true)
      ...MilestoneMetadata @arguments(includeMilestone: $includeMilestone)
    }

    ... on PullRequest {
      createdAt
      updatedAt
      closed
      closedAt
      author {
        login
        resourcePath
        __typename
        ... on Bot {
          isCopilot
        }
      }
      number
      ...MilestoneMetadata @arguments(includeMilestone: $includeMilestone)
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
  const {pull_request_single_subscription} = useFeatureFlags()

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

  const authorType = author?.__typename
  const authorLogin = author?.login || VALUES.ghostUserLogin
  const authorFullLogin = authorType === 'Bot' ? `app/${authorLogin}` : authorLogin
  const isCopilot = author?.isCopilot
  const displayName = isCopilot ? VALUES.copilotDisplayName : authorLogin
  const resourcePath = author?.resourcePath || ''
  const hovercardAttributes = hovercardAttributesForActor(authorLogin, {isCopilot})
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
      {variant === 'default' && (
        <>
          {closed ? (
            <TimestampContainer
              displayName={displayName}
              authorFullLogin={authorFullLogin}
              resourcePath={resourcePath}
              getAuthorHref={getAuthorHref}
              hovercardAttributes={hovercardAttributes}
              timestamp={closedAt}
              testId="closed-at"
              action={ActionType.Closed}
            />
          ) : (
            <TimestampContainer
              displayName={displayName}
              authorFullLogin={authorFullLogin}
              resourcePath={resourcePath}
              getAuthorHref={getAuthorHref}
              hovercardAttributes={hovercardAttributes}
              timestamp={createdAt}
              testId="created-at"
              action={ActionType.Opened}
            />
          )}
          {(sortingItemSelected === LABELS.RecentlyUpdated || sortingItemSelected === 'updated') && updatedAt && (
            <div data-testid="updated-at" className={styles.timestampContainer}>
              {' '}
              &middot; Updated{' '}
              <RelativeTime date={updatedAt} sx={{verticalAlign: 'bottom'}}>
                on {updatedAt.toLocaleDateString('en-US', {month: 'short', day: 'numeric', year: 'numeric'})}
              </RelativeTime>
            </div>
          )}
        </>
      )}
      {stateReason?.toLowerCase() === 'duplicate' && <span data-testid="state-reason"> &middot;{' Duplicate'}</span>}
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

const ActionType = {
  Opened: 'opened',
  Closed: 'closed',
} as const

type ActionType = (typeof ActionType)[keyof typeof ActionType]

const TimestampContainer = ({
  displayName,
  authorFullLogin,
  resourcePath,
  getAuthorHref,
  hovercardAttributes,
  timestamp,
  testId,
  action,
}: {
  displayName: string
  authorFullLogin: string
  resourcePath: string
  getAuthorHref?: (resourcePath: string) => string
  hovercardAttributes: HovercardAttributes
  timestamp?: Date
  testId: string
  action: ActionType
}) => (
  <div data-testid={testId} className={styles.timestampContainer}>
    <span>&middot; </span>
    <span>{action === ActionType.Closed && ' by '}</span>
    <Link
      href={getAuthorHref ? getAuthorHref(authorFullLogin) : resourcePath}
      className={styles.authorCreatedLink}
      {...hovercardAttributes}
    >
      {displayName}
    </Link>{' '}
    <span>{action === ActionType.Opened ? ` opened ` : ` was closed `}</span>
    {timestamp && (
      <RelativeTime date={timestamp}>
        on {timestamp.toLocaleDateString('en-US', {month: 'short', day: 'numeric', year: 'numeric'})}
      </RelativeTime>
    )}
  </div>
)

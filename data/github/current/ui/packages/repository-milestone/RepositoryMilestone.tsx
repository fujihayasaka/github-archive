import {graphql, useFragment} from 'react-relay'
import type {RepositoryMilestone$key} from './__generated__/RepositoryMilestone.graphql'
import {ListView} from '@github-ui/list-view'
import {testIdProps} from '@github-ui/test-id-props'
import {IssueRow, IssuesIndexSecondaryGraphqlQuery} from '@github-ui/list-view-items-issues-prs/IssueRow'
import {noop} from '@github-ui/noop'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import type {SsoAppPayload} from '@github-ui/use-sso'
import type {UserHookPayload} from '@github-ui/use-user'
import {ListViewMetadata} from '@github-ui/list-view/ListViewMetadata'
import {ThreePanesLayout} from '@github-ui/three-panes-layout'
import styles from './RepositoryMilestone.module.css'
import {useNavigate} from '@github-ui/use-navigate'
import {prefetchIssue} from '@github-ui/issue-viewer/IssueViewerLoader'
import {Suspense, useCallback, useEffect, useMemo} from 'react'
import type {NavigateOptions, To} from 'react-router-dom'
import {usePreloadedQuery, useQueryLoader, useRelayEnvironment, type PreloadedQuery} from 'react-relay/hooks'
import {startSoftNav} from '@github-ui/soft-nav/state'
import type {RepositoryMilestoneQuery} from './__generated__/RepositoryMilestoneQuery.graphql'
import {Heading, ProgressBar, StateLabel, RelativeTime} from '@primer/react'
import {AlertFillIcon} from '@primer/octicons-react'
import {MarkdownViewer} from '@github-ui/markdown-viewer'
import type {SafeHTMLString} from '@github-ui/safe-html'
import type {IssueRowSecondaryQuery} from '@github-ui/list-view-items-issues-prs/IssueRowSecondaryQuery'
import {IS_SERVER} from '@github-ui/ssr-utils'
import {OpenClosedMilestoneIssues} from './OpenClosedMilestoneIssues'
export interface RepositoryMilestoneProps {
  exampleMessage: string
}

export const RepositoryMilestonePageQuery = graphql`
  query RepositoryMilestoneQuery(
    $owner: String!
    $name: String!
    $number: Int!
    $first: Int!
    $states: [IssueState!]!
  ) {
    repository(owner: $owner, name: $name) {
      ...RepositoryMilestone @arguments(first: $first, number: $number, states: $states)
      milestone(number: $number) {
        title
      }
    }
  }
`

// TODO make this sharable and use it too in IssuesReact
type AppPayload = {
  enabled_features: {[key: string]: boolean}
  initial_view_content: {
    team_id: string | undefined
    can_edit_view: boolean
  }
  current_user: {
    avatarUrl: string
    id: string
    login: string
    name: string
    is_staff: boolean
  }
  current_user_settings: {
    use_monospace_font: boolean
    use_single_key_shortcut: boolean
    preferred_emoji_skin_tone?: number
  }
  paste_url_link_as_plain_text: boolean
  tracing: boolean
  tracing_flamegraph: boolean
  catalog_service: string
  scoped_repository?: {id: string; name: string; owner: string; is_archived: boolean}
} & SsoAppPayload &
  UserHookPayload

export const RepositoryMilestone = ({queryRef}: {queryRef: PreloadedQuery<RepositoryMilestoneQuery>}) => {
  const [pageQueryRef] = useQueryLoader<RepositoryMilestoneQuery>(RepositoryMilestonePageQuery, queryRef)
  if (!pageQueryRef) return null

  return (
    <Suspense fallback={<div>Loading...</div>}>
      <RepositoryMilestoneContent pageQueryRef={pageQueryRef} />
    </Suspense>
  )
}

function RepositoryMilestoneContent({pageQueryRef}: {pageQueryRef: PreloadedQuery<RepositoryMilestoneQuery>}) {
  const pageData = usePreloadedQuery<RepositoryMilestoneQuery>(RepositoryMilestonePageQuery, pageQueryRef)

  if (!pageData.repository) return null

  return <RepositoryMilestoneInternal repository={pageData.repository} />
}

export function RepositoryMilestoneInternal({repository}: {repository: RepositoryMilestone$key}) {
  const data = useFragment(
    graphql`
      fragment RepositoryMilestone on Repository
      @argumentDefinitions(first: {type: "Int!"}, number: {type: "Int!"}, states: {type: "[IssueState!]!"}) {
        milestone(number: $number) {
          title
          closed
          dueOn
          updatedAt
          description
          descriptionHTML
          progressPercentage
          issues(first: $first, states: $states) {
            edges {
              node {
                id
                number
                ...IssueRow @arguments(labelPageSize: 10, fetchRepository: false, includeMilestone: false)
              }
            }
          }
          ...OpenClosedMilestoneIssues
        }
      }
    `,
    repository,
  )

  const {scoped_repository} = useAppPayload<AppPayload>()
  const nodes = useMemo(
    () => data.milestone?.issues?.edges?.map(edge => edge?.node).filter(node => !!node) || [],
    [data],
  )
  const nodesIds = useMemo(() => nodes?.map(node => node?.id).filter(Boolean), [nodes])
  const [milestoneIssuesLazyDataRef, loadMilestoneIssuesLazyData] = useQueryLoader<IssueRowSecondaryQuery>(
    IssuesIndexSecondaryGraphqlQuery,
  )
  const hasLazyData = milestoneIssuesLazyDataRef !== null
  useEffect(() => {
    if (!IS_SERVER) {
      loadMilestoneIssuesLazyData({nodes: nodesIds, includeReactions: false})
    }
  }, [loadMilestoneIssuesLazyData, nodesIds, hasLazyData])

  const environment = useRelayEnvironment()
  const navigate = useNavigate()
  const handleNavigate = useCallback(
    async ({issueNumber}: {issueNumber: number}, to: To, navOptions?: NavigateOptions) => {
      if (!scoped_repository) return navigate(to, navOptions)
      startSoftNav('react')
      await prefetchIssue(environment, scoped_repository.owner, scoped_repository.name, issueNumber)
      return navigate(to, navOptions)
    },
    [environment, navigate, scoped_repository],
  )

  const items = nodes?.map(node => {
    const sharedRowData = {
      key: node?.id,
      isActive: false,
      isSelected: false,
      onSelect: noop, //(selected: boolean) => node && itemSelected(node.id, node, selected),
      onSelectRow: noop,
      getMetadataHref: () => "test'",
      reactionEmojiToDisplay: {reaction: '', reactionEmoji: ''},
      sortingItemSelected: '',
      onNavigate: (to: To, navOptions?: NavigateOptions) => handleNavigate({issueNumber: node.number}, to, navOptions),
      scopedRepository: scoped_repository,
      metadataRef: milestoneIssuesLazyDataRef,
    }
    return <IssueRow issueKey={node} {...sharedRowData} key={sharedRowData.key} />
  })

  const currentMilestone = data.milestone

  const totalOverDue = useMemo(() => {
    if (!currentMilestone || !currentMilestone.dueOn) return null
    const dueOn = new Date(currentMilestone.dueOn)
    const today = new Date()

    if (dueOn > today) return null

    // Set both dates to midnight to avoid partial day errors
    today.setHours(0, 0, 0, 0)
    dueOn.setHours(0, 0, 0, 0)

    const diffTime = today.getTime() - dueOn.getTime()

    const diffDays = Math.floor(diffTime / (1000 * 60 * 60 * 24))

    if (diffDays < 30) {
      return `${diffDays} day(s)`
    }

    const diffMonths = Math.floor(diffDays / 30)
    if (diffMonths < 12) {
      return `${diffMonths} month(s)`
    }

    const diffYears = Math.floor(diffMonths / 12)
    return `${diffYears} year(s)`
  }, [currentMilestone])

  if (!currentMilestone) return null

  let formattedDate = ''
  if (currentMilestone.dueOn) {
    formattedDate = new Date(currentMilestone.dueOn).toLocaleDateString('default', {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
    })
  }
  const listItemsHeader = (
    <ListViewMetadata
      sectionFilters={<OpenClosedMilestoneIssues milestoneRef={data.milestone} />}
      onToggleSelectAll={noop}
      density={'condensed'}
      actionsLabel="Actions"
      actions={[]}
    />
  )
  return (
    <ThreePanesLayout
      contentAs="div"
      resizeable={false}
      leftPaneWidth="small"
      middlePane={
        <div className={styles.middlePaneGrid}>
          <Heading as="h3">{currentMilestone.title}</Heading>
          <div className={styles.wrapper}>
            <div className={styles.status} data-testid="milestone-status">
              <StateLabel variant="small" status={currentMilestone.closed ? 'issueClosed' : 'issueOpened'}>
                {currentMilestone.closed ? 'Closed' : 'Open'}
              </StateLabel>
              {totalOverDue ? (
                <>
                  <div className={styles.overDue}>
                    <AlertFillIcon size={12} />
                    <span>Overdue by {totalOverDue}</span>
                  </div>
                  <span>•</span>
                </>
              ) : null}
              <>
                {currentMilestone.dueOn ? <span>Due by {formattedDate}</span> : <span>No due date</span>}
                <span>•</span>
              </>
              <span>
                {currentMilestone.closed ? <>Closed </> : <>Last updated at </>}
                <RelativeTime date={new Date(currentMilestone.updatedAt)} tense="past" />
              </span>
            </div>
            {currentMilestone.description && currentMilestone.descriptionHTML ? (
              <div>
                <MarkdownViewer
                  markdownValue={currentMilestone.description}
                  verifiedHTML={currentMilestone.descriptionHTML as SafeHTMLString}
                  onChange={() => {}}
                />
              </div>
            ) : null}
            <div className={styles.progressSection}>
              <span>
                <span className={styles.progressPercentage}>{Math.round(currentMilestone.progressPercentage)}%</span>{' '}
                complete
              </span>
              <ProgressBar progress={Math.round(currentMilestone.progressPercentage)} role="presentation" />
            </div>
          </div>
          <ListView
            {...testIdProps('repository-milestone-list-view')}
            title=""
            // totalCount={pageData.search?.issueCount || 0}
            // selectedCount={checkedItems.size}
            titleHeaderTag="h2"
            isSelectable={false}
            metadata={listItemsHeader}
            singularUnits={'issue'}
            pluralUnits={'issues'}
            // listRef={listRef}
          >
            {items}
            {/* {items.length === 0 && searchResultsReady && <NoResults />} */}
          </ListView>
        </div>
      }
    />
  )
}

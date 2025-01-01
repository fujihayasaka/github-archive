import {ThreePanesLayout} from '@github-ui/three-panes-layout'
import {
  type EntryPointComponent,
  type PreloadedQuery,
  useLazyLoadQuery,
  graphql,
  usePreloadedQuery,
  type UseQueryLoaderLoadQueryOptions,
} from 'react-relay'

import {useEntryPointsLoader} from '../hooks/use-entrypoint-loaders'
import type {ClientSideRelayDataGeneratorViewQuery} from './__generated__/ClientSideRelayDataGeneratorViewQuery.graphql'
import {AnalyticsWrapper} from './AnalyticsWrapper'
import {currentViewQuery as currentView} from './ClientSideRelayDataGenerator'
import {JobInfoWithSubscription} from '@github-ui/issues-bulk-actions/JobInfoWithSubscription'
import {List} from './List'
import {VIEW_IDS} from '@github-ui/issue-url-helper/constants/view-constants'
import type {IssueIndexPageQuery, IssueIndexPageQuery$variables} from './__generated__/IssueIndexPageQuery.graphql'
import {useEffect} from 'react'
import {useQueryContext, useQueryEditContext} from '../contexts/QueryContext'
import {PinnedIssues} from '../components/pinnedIssues/PinnedIssues'
import {FirstTimeContributionBanner} from '../components/firstTimeContributionBanner/FirstTimeContributionBanner'
import {IndexSidebar} from '../components/sidebar/IndexSidebar'
import {LABELS} from '../constants/labels'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import MobileNavigation from '../components/sidebar/MobileNavigation'
import styles from './IssueIndexPage.module.css'
import {Stack} from '@primer/react'
import {FeatureFlags} from '@primer/react/experimental'
import {CallToActionItem} from '../components/CallToActionItem'
import {SemanticSearchPreviewOptIn} from '../components/SemanticSearchPreviewOptIn'

const PageQuery = graphql`
  query IssueIndexPageQuery(
    $query: String = "state:open archived:false assignee:@me sort:updated-desc"
    $first: Int = 25
    $labelPageSize: Int = 20
    $skip: Int = null
    $name: String!
    $owner: String!
  ) {
    repository(owner: $owner, name: $name) {
      ...PinnedIssues
      ...ListRepositoryFragment
      ...FirstTimeContributionBanner
      ...ListQuery
        @arguments(query: $query, first: $first, labelPageSize: $labelPageSize, skip: $skip, fetchRepository: false)
    }
    safeViewer {
      # this is intentional to have the current viewer preloaded for the item pickers
      # eslint-disable-next-line relay/must-colocate-fragment-spreads
      ...AssigneePickerAssignee
    }
  }
`

export const IssueIndexPage: EntryPointComponent<{pageQuery: IssueIndexPageQuery}, Record<string, never>> = ({
  queries: {pageQuery},
}) => {
  const {queryRef, loadQuery} = useEntryPointsLoader(pageQuery, PageQuery)

  const {setCurrentViewId} = useQueryContext()

  useEffect(() => {
    setCurrentViewId(VIEW_IDS.repository)
  }, [pageQuery, setCurrentViewId])

  if (!queryRef) return null

  return <IssueIndexPageContent pageQueryRef={queryRef} loadQuery={loadQuery} />
}

function IssueIndexPageContent({
  pageQueryRef,
  loadQuery,
}: {
  pageQueryRef: PreloadedQuery<IssueIndexPageQuery>
  loadQuery: (variables: IssueIndexPageQuery$variables, options?: UseQueryLoaderLoadQueryOptions | undefined) => void
}) {
  const currentViewNode = useLazyLoadQuery<ClientSideRelayDataGeneratorViewQuery>(
    currentView,
    {id: VIEW_IDS.repository},
    {fetchPolicy: 'store-only'},
  )

  const {bulkJobId, setBulkJobId} = useQueryEditContext()

  const pageData = usePreloadedQuery<IssueIndexPageQuery>(PageQuery, pageQueryRef)
  const indexQuickFiltersEnabled = isFeatureEnabled('issues_react_index_quick_filters')

  const flags = {
    primer_react_select_panel_with_modern_action_list: true,
  }

  if (!pageData.repository) return null

  return (
    <AnalyticsWrapper category="Issues Index">
      <JobInfoWithSubscription bulkJobId={bulkJobId} setBulkJobId={setBulkJobId}>
        <ThreePanesLayout
          contentAs="div"
          resizeable={false}
          leftPaneWidth="small"
          leftPane={
            indexQuickFiltersEnabled
              ? {
                  element: <IndexSidebar />,
                  ariaLabel: LABELS.viewSidebarPaneAriaLabel,
                }
              : undefined
          }
          middlePane={
            <>
              <div className={styles.middlePaneGrid}>
                {!indexQuickFiltersEnabled && (
                  <Stack gap="condensed" direction="horizontal">
                    <SemanticSearchPreviewOptIn />
                    <div className="flex-1" />
                    <CallToActionItem />
                  </Stack>
                )}

                <FirstTimeContributionBanner repository={pageData.repository} />
                <PinnedIssues repository={pageData.repository} />
                {currentViewNode.node ? (
                  <FeatureFlags flags={flags}>
                    <List
                      fetchedView={currentViewNode.node}
                      fetchedRepository={pageData.repository}
                      search={pageData.repository}
                      loadSearchQuery={loadQuery}
                    />
                  </FeatureFlags>
                ) : null}
              </div>
            </>
          }
        />
        <MobileNavigation />
      </JobInfoWithSubscription>
    </AnalyticsWrapper>
  )
}

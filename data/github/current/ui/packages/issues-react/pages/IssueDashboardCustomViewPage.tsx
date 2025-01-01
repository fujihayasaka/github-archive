import {ThreePanesLayout} from '@github-ui/three-panes-layout'
import {useCallback, useEffect} from 'react'
import {
  graphql,
  type EntryPointComponent,
  type PreloadedQuery,
  usePreloadedQuery,
  type UseQueryLoaderLoadQueryOptions,
} from 'react-relay'
import {useLocation} from 'react-router-dom'

import type {SavedViewsQuery} from '../components/sidebar/__generated__/SavedViewsQuery.graphql'
import MobileNavigation from '../components/sidebar/MobileNavigation'
import {SavedViewsGraphqlQuery as customViews} from '../components/sidebar/SavedViews'
import {Sidebar} from '../components/sidebar/Sidebar'
import {useEntryPointsLoader} from '../hooks/use-entrypoint-loaders'
import type {ClientSideRelayDataGeneratorViewQuery} from './__generated__/ClientSideRelayDataGeneratorViewQuery.graphql'
import {AnalyticsWrapper} from './AnalyticsWrapper'
import {currentViewQuery as currentView} from './ClientSideRelayDataGenerator'
import {ListWithFetchedView} from './List'
import {LABELS} from '../constants/labels'
import {VIEW_IDS} from '../constants/view-constants'
import {useQueryContext} from '../contexts/QueryContext'
import type {
  IssueDashboardCustomViewPageQuery,
  IssueDashboardCustomViewPageQuery$variables,
} from './__generated__/IssueDashboardCustomViewPageQuery.graphql'
import {IssueViewer} from '@github-ui/issue-viewer/IssueViewer'
import {ISSUE_VIEWER_DEFAULT_CONFIG} from '@github-ui/issue-viewer/OptionConfig'
import type {ItemIdentifier} from '@github-ui/issue-viewer/Types'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import type {SubIssueSidePanelItem} from '@github-ui/sub-issues/sub-issue-types'
import {ScreenFullIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import {IssueSidePanel} from '../components/show/IssueSidePanel'
import {useRouteInfo} from '../hooks/use-route-info'
import type {AppPayload} from '../types/app-payload'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'

const PageQuery = graphql`
  query IssueDashboardCustomViewPageQuery(
    $query: String = "state:open archived:false assignee:@me sort:updated-desc"
    $first: Int = 25
    $labelPageSize: Int = 20
    $skip: Int = null
  ) {
    ...ListQuery
      @arguments(query: $query, first: $first, labelPageSize: $labelPageSize, skip: $skip, fetchRepository: true)
  }
`

export const IssueDashboardCustomViewPage: EntryPointComponent<
  {
    pageQuery: IssueDashboardCustomViewPageQuery
    currentViewQuery: ClientSideRelayDataGeneratorViewQuery
    customViewsQuery: SavedViewsQuery
  },
  Record<string, never>
> = ({queries: {pageQuery, currentViewQuery, customViewsQuery}}) => {
  const appPayload = useAppPayload<AppPayload>()
  const singleKeyShortcutsEnabled = appPayload?.current_user_settings?.use_single_key_shortcut || false

  const {
    sidePanelItemIdentifier,
    setSidePanelItemIdentifier,
    sidePanelItemURL,
    onCloseSidePanel,
    onParentIssueActivate,
  } = useRouteInfo()
  const {queryRef: pageQueryRef, loadQuery: loadQuery} = useEntryPointsLoader(pageQuery, PageQuery)
  const {queryRef: currentViewRef} = useEntryPointsLoader(currentViewQuery, currentView)
  const {queryRef: customViewsRef} = useEntryPointsLoader(customViewsQuery, customViews)
  const shouldUseSidePanel = useFeatureFlag('issues_dashboard_use_sidepanel')

  const {setCurrentViewId} = useQueryContext()

  const {pathname} = useLocation()
  const id = pathname.split('/').pop()

  useEffect(() => {
    setCurrentViewId(id ? id : VIEW_IDS.empty)
  }, [id, pageQuery, setCurrentViewId])

  const onSubIssueClick = useCallback(
    (subIssueItem: SubIssueSidePanelItem) => {
      const {owner, repo, number} = subIssueItem
      setSidePanelItemIdentifier({owner, repo, number, type: 'Issue'})
    },
    [setSidePanelItemIdentifier],
  )

  if (!currentViewRef) return null
  if (!pageQueryRef) return null
  if (!customViewsRef) return null

  return (
    <>
      <IssueDashboardCustomViewPageContent
        pageQueryRef={pageQueryRef}
        currentViewQueryRef={currentViewRef}
        loadQuery={loadQuery}
        savedViewsQueryRef={customViewsRef}
        onSidePanelNavigate={shouldUseSidePanel ? setSidePanelItemIdentifier : undefined}
      />
      {shouldUseSidePanel && sidePanelItemIdentifier && (
        <IssueSidePanel onClose={onCloseSidePanel}>
          <IssueViewer
            itemIdentifier={sidePanelItemIdentifier}
            optionConfig={Object.assign({}, ISSUE_VIEWER_DEFAULT_CONFIG, {
              shouldSkipSetDocumentTitle: true,
              onClose: onCloseSidePanel,
              insideSidePanel: true,
              singleKeyShortcutsEnabled,
              onSubIssueClick,
              onParentIssueActivate,
              navigateBack: onCloseSidePanel,
              additionalHeaderActions: (
                <IconButton
                  as="a"
                  role="link"
                  variant="invisible"
                  icon={ScreenFullIcon}
                  aria-label={LABELS.sidePanelTooltip}
                  href={sidePanelItemURL}
                />
              ),
            })}
          />
        </IssueSidePanel>
      )}
    </>
  )
}

function IssueDashboardCustomViewPageContent({
  pageQueryRef,
  loadQuery,
  currentViewQueryRef,
  savedViewsQueryRef,
  onSidePanelNavigate,
}: {
  pageQueryRef: PreloadedQuery<IssueDashboardCustomViewPageQuery>
  currentViewQueryRef: PreloadedQuery<ClientSideRelayDataGeneratorViewQuery>
  savedViewsQueryRef: PreloadedQuery<SavedViewsQuery>
  loadQuery: (
    variables: IssueDashboardCustomViewPageQuery$variables,
    options?: UseQueryLoaderLoadQueryOptions | undefined,
  ) => void
  onSidePanelNavigate?: (issue: ItemIdentifier) => void
}) {
  const data = usePreloadedQuery<IssueDashboardCustomViewPageQuery>(PageQuery, pageQueryRef)

  return (
    <AnalyticsWrapper category="Issues Dashboard">
      <ThreePanesLayout
        leftPane={{
          element: <Sidebar customViewsRef={savedViewsQueryRef} />,
          ariaLabel: LABELS.viewSidebarPaneAriaLabel,
        }}
        middlePane={
          <ListWithFetchedView
            currentViewRef={currentViewQueryRef}
            fetchedRepository={null}
            search={data}
            loadSearchQuery={loadQuery}
            onSidePanelNavigate={onSidePanelNavigate}
          />
        }
      />
      <MobileNavigation customViewsRef={savedViewsQueryRef} />
    </AnalyticsWrapper>
  )
}

import {ThreePanesLayout} from '@github-ui/three-panes-layout'
import {useCallback, useEffect} from 'react'
import {
  type EntryPointComponent,
  type PreloadedQuery,
  useLazyLoadQuery,
  graphql,
  usePreloadedQuery,
  type UseQueryLoaderLoadQueryOptions,
} from 'react-relay'
import {useLocation} from 'react-router-dom'

import type {SavedViewsQuery} from '../components/sidebar/__generated__/SavedViewsQuery.graphql'
import MobileNavigation from '../components/sidebar/MobileNavigation'
import {SavedViewsGraphqlQuery as customViews} from '../components/sidebar/SavedViews'
import {Sidebar} from '../components/sidebar/Sidebar'
import {LABELS} from '../constants/labels'
import {ASSIGNED_TO_ME_VIEW, EMPTY_VIEW} from '../constants/view-constants'
import {useEntryPointsLoader} from '../hooks/use-entrypoint-loaders'
import type {ClientSideRelayDataGeneratorViewQuery} from './__generated__/ClientSideRelayDataGeneratorViewQuery.graphql'
import {AnalyticsWrapper} from './AnalyticsWrapper'
import {currentViewQuery as currentView} from './ClientSideRelayDataGenerator'
import {List} from './List'
import {useQueryContext} from '../contexts/QueryContext'
import {useAppNavigate} from '../hooks/use-app-navigate'
import type {
  IssueDashboardPageQuery,
  IssueDashboardPageQuery$variables,
} from './__generated__/IssueDashboardPageQuery.graphql'
import type {AppPayload} from '../types/app-payload'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {useRouteInfo} from '../hooks/use-route-info'
import type {ItemIdentifier} from '@github-ui/issue-viewer/Types'
import type {SubIssueSidePanelItem} from '@github-ui/sub-issues/sub-issue-types'
import {IssueViewer} from '@github-ui/issue-viewer/IssueViewer'
import {ISSUE_VIEWER_DEFAULT_CONFIG} from '@github-ui/issue-viewer/OptionConfig'
import {ScreenFullIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import {IssueSidePanel} from '../components/show/IssueSidePanel'

const PageQuery = graphql`
  query IssueDashboardPageQuery(
    $query: String = "state:open archived:false assignee:@me sort:updated-desc"
    $first: Int = 25
    $labelPageSize: Int = 20
    $skip: Int = null
  ) {
    ...ListQuery
      @arguments(query: $query, first: $first, labelPageSize: $labelPageSize, skip: $skip, fetchRepository: true)
  }
`

export const IssueDashboardPage: EntryPointComponent<
  {pageQuery: IssueDashboardPageQuery; customViewsQuery: SavedViewsQuery},
  Record<string, never>
> = ({queries: {pageQuery, customViewsQuery}}) => {
  const appPayload = useAppPayload<AppPayload>()
  const singleKeyShortcutsEnabled = appPayload?.current_user_settings?.use_single_key_shortcut || false

  const {
    sidePanelItemIdentifier,
    setSidePanelItemIdentifier,
    sidePanelItemURL,
    onCloseSidePanel,
    onParentIssueActivate,
  } = useRouteInfo()
  const {queryRef: pageQueryRef, loadQuery} = useEntryPointsLoader(pageQuery, PageQuery)
  const {queryRef: savedViewsQueryRef} = useEntryPointsLoader(customViewsQuery, customViews)

  const {navigateToView} = useAppNavigate()
  const {search} = useLocation()

  const onSubIssueClick = useCallback(
    (subIssueItem: SubIssueSidePanelItem) => {
      const {owner, repo, number} = subIssueItem
      setSidePanelItemIdentifier({owner, repo, number, type: 'Issue'})
    },
    [setSidePanelItemIdentifier],
  )

  if (!pageQueryRef) return null
  if (!savedViewsQueryRef) return null

  const urlSearchParams = new URLSearchParams(search)
  const urlQuery = urlSearchParams.get('q')

  if (!urlQuery) {
    navigateToView({viewId: ASSIGNED_TO_ME_VIEW.id, canEditView: true})
    return null
  }
  return (
    <>
      <IssueDashboardPageContent
        pageQueryRef={pageQueryRef}
        loadQuery={loadQuery}
        savedViewsQueryRef={savedViewsQueryRef}
        onSidePanelNavigate={setSidePanelItemIdentifier}
      />
      {sidePanelItemIdentifier && (
        <IssueSidePanel onClose={onCloseSidePanel}>
          <IssueViewer
            itemIdentifier={sidePanelItemIdentifier}
            optionConfig={Object.assign({}, ISSUE_VIEWER_DEFAULT_CONFIG, {
              shouldSkipSetDocumentTitle: true,
              onClose: onCloseSidePanel,
              insideSidePanel: true,
              showRepositoryPill: true,
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

function IssueDashboardPageContent({
  pageQueryRef,
  loadQuery,
  savedViewsQueryRef,
  onSidePanelNavigate,
}: {
  pageQueryRef: PreloadedQuery<IssueDashboardPageQuery>
  savedViewsQueryRef: PreloadedQuery<SavedViewsQuery>
  loadQuery: (
    variables: IssueDashboardPageQuery$variables,
    options?: UseQueryLoaderLoadQueryOptions | undefined,
  ) => void
  onSidePanelNavigate?: (issue: ItemIdentifier) => void
}) {
  const {setCurrentViewId} = useQueryContext()

  useEffect(() => {
    setCurrentViewId(EMPTY_VIEW.id)
  }, [setCurrentViewId])

  const currentViewNode = useLazyLoadQuery<ClientSideRelayDataGeneratorViewQuery>(
    currentView,
    {id: EMPTY_VIEW.id},
    {fetchPolicy: 'store-only'},
  )

  const data = usePreloadedQuery<IssueDashboardPageQuery>(PageQuery, pageQueryRef)

  if (!currentViewNode || !currentViewNode.node) return null

  return (
    <AnalyticsWrapper category="Issues Dashboard">
      <ThreePanesLayout
        leftPaneWidth={'small'}
        leftPane={{
          element: <Sidebar customViewsRef={savedViewsQueryRef} />,
          ariaLabel: LABELS.viewSidebarPaneAriaLabel,
        }}
        middlePane={
          <List
            fetchedView={currentViewNode.node}
            fetchedRepository={null}
            search={data}
            loadSearchQuery={loadQuery}
            onSidePanelNavigate={onSidePanelNavigate}
            showSsoBanner
          />
        }
      />
      <MobileNavigation customViewsRef={savedViewsQueryRef} />
    </AnalyticsWrapper>
  )
}

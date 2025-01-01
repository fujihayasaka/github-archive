import {ThreePanesLayout} from '@github-ui/three-panes-layout'
import {Suspense, useCallback, useEffect} from 'react'
import {graphql, useFragment, usePreloadedQuery, type EntryPointComponent, type PreloadedQuery} from 'react-relay'
import {useLocation} from 'react-router-dom'

import {VIEW_IDS} from '@github-ui/issue-url-helper/constants/view-constants'
import {IssueViewer} from '@github-ui/issue-viewer/IssueViewer'
import {ISSUE_VIEWER_DEFAULT_CONFIG} from '@github-ui/issue-viewer/OptionConfig'
import type {ItemIdentifier} from '@github-ui/issue-viewer/Types'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import type {SubIssueSidePanelItem} from '@github-ui/sub-issues/sub-issue-types'
import {ScreenFullIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import {Header} from '../components/list/header/Header'
import {HeaderLoading} from '../components/list/header/HeaderLoading'
import {DashboardSearch} from '../components/dashboard/DashboardSearch'
import {IssueSidePanel} from '../components/show/IssueSidePanel'
import type {SavedViewsQuery} from '../components/sidebar/__generated__/SavedViewsQuery.graphql'
import MobileNavigation from '../components/sidebar/MobileNavigation'
import {SavedViewsGraphqlQuery as customViews} from '../components/sidebar/SavedViews'
import {Sidebar} from '../components/sidebar/Sidebar'
import {LABELS} from '../constants/labels'
import {useQueryContext} from '../contexts/QueryContext'
import {useEntryPointsLoader} from '../hooks/use-entrypoint-loaders'
import {useRouteInfo} from '../hooks/use-route-info'
import type {AppPayload} from '../types/app-payload'
import type {ClientSideRelayDataGeneratorViewQuery} from './__generated__/ClientSideRelayDataGeneratorViewQuery.graphql'
import type {IssueDashboardCustomViewPageQuery} from './__generated__/IssueDashboardCustomViewPageQuery.graphql'
import {AnalyticsWrapper} from './AnalyticsWrapper'
import {currentViewQuery as currentView} from './ClientSideRelayDataGenerator'
import type {IssueDashboardCustomViewPageSearchListFragment$key} from './__generated__/IssueDashboardCustomViewPageSearchListFragment.graphql'
import type {IssueDashboardCustomViewPageCurrentViewFragment$key} from './__generated__/IssueDashboardCustomViewPageCurrentViewFragment.graphql'
import styles from './IssueDashboardCustomViewPage.module.css'

const PageQuery = graphql`
  query IssueDashboardCustomViewPageQuery(
    $query: String = "state:open archived:false assignee:@me sort:updated-desc"
    $first: Int = 25
    $labelPageSize: Int = 20
    $skip: Int = null
  ) {
    ...IssueDashboardCustomViewPageSearchListFragment
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
  const {queryRef: pageQueryRef} = useEntryPointsLoader(pageQuery, PageQuery)
  const {queryRef: currentViewRef} = useEntryPointsLoader(currentViewQuery, currentView)
  const {queryRef: customViewsRef} = useEntryPointsLoader(customViewsQuery, customViews)

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
        savedViewsQueryRef={customViewsRef}
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

const SearchListFragment = graphql`
  fragment IssueDashboardCustomViewPageSearchListFragment on Searchable
  @argumentDefinitions(
    query: {type: "String!"}
    first: {type: "Int"}
    labelPageSize: {type: "Int!"}
    skip: {type: "Int", defaultValue: null}
    fetchRepository: {type: "Boolean!"}
  ) {
    ...DashboardSearchFragment
      @arguments(
        query: $query
        first: $first
        labelPageSize: $labelPageSize
        skip: $skip
        fetchRepository: $fetchRepository
      )
  }
`

const CurrentViewFragment = graphql`
  fragment IssueDashboardCustomViewPageCurrentViewFragment on Shortcutable {
    ...HeaderCurrentViewFragment
  }
`

function IssueDashboardCustomViewPageContent({
  pageQueryRef,
  currentViewQueryRef,
  savedViewsQueryRef,
  onSidePanelNavigate,
}: {
  pageQueryRef: PreloadedQuery<IssueDashboardCustomViewPageQuery>
  currentViewQueryRef: PreloadedQuery<ClientSideRelayDataGeneratorViewQuery>
  savedViewsQueryRef: PreloadedQuery<SavedViewsQuery>
  onSidePanelNavigate?: (issue: ItemIdentifier) => void
}) {
  const {itemIdentifier} = useRouteInfo()
  const data = usePreloadedQuery<IssueDashboardCustomViewPageQuery>(PageQuery, pageQueryRef)
  const currentViewEncapsulated = usePreloadedQuery<ClientSideRelayDataGeneratorViewQuery>(
    currentView,
    currentViewQueryRef,
  )

  const searchListData = useFragment<IssueDashboardCustomViewPageSearchListFragment$key>(SearchListFragment, data)
  const currentViewData = useFragment<IssueDashboardCustomViewPageCurrentViewFragment$key>(
    CurrentViewFragment,
    currentViewEncapsulated.node,
  )

  if (!currentViewEncapsulated.node || !currentViewData || !savedViewsQueryRef) {
    return null
  }

  return (
    <AnalyticsWrapper category="Issues Dashboard">
      <ThreePanesLayout
        leftPaneWidth={'small'}
        leftPane={{
          element: <Sidebar customViewsRef={savedViewsQueryRef} isFullHeight />,
          ariaLabel: LABELS.viewSidebarPaneAriaLabel,
        }}
        middlePane={
          <div className={styles.searchListContainer}>
            <Suspense fallback={<HeaderLoading />}>
              <Header
                setSafeDocumentTitle={!!itemIdentifier?.number}
                currentViewKey={currentViewData}
                currentRepository={null}
              />
            </Suspense>
            <DashboardSearch
              currentView={currentViewEncapsulated.node}
              onSidePanelNavigate={onSidePanelNavigate}
              itemIdentifier={itemIdentifier}
              search={searchListData}
            />
          </div>
        }
      />
      <MobileNavigation customViewsRef={savedViewsQueryRef} />
    </AnalyticsWrapper>
  )
}

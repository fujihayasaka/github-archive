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

import {useEntryPointsLoader} from '../hooks/use-entrypoint-loaders'
import type {ClientSideRelayDataGeneratorViewQuery} from './__generated__/ClientSideRelayDataGeneratorViewQuery.graphql'
import {AnalyticsWrapper} from './AnalyticsWrapper'
import {currentViewQuery as currentView} from './ClientSideRelayDataGenerator'
import {List} from './List'
import {LABELS} from '../constants/labels'
import {VIEW_IDS} from '@github-ui/issue-url-helper/constants/view-constants'
import {useQueryContext} from '../contexts/QueryContext'
import type {
  IssueDashboardKnownViewPageQuery,
  IssueDashboardKnownViewPageQuery$variables,
} from './__generated__/IssueDashboardKnownViewPageQuery.graphql'
import {useRouteInfo} from '../hooks/use-route-info'
import type {ItemIdentifier} from '@github-ui/issue-viewer/Types'
import {IssueViewer} from '@github-ui/issue-viewer/IssueViewer'
import {ISSUE_VIEWER_DEFAULT_CONFIG} from '@github-ui/issue-viewer/OptionConfig'
import {ScreenFullIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import {IssueSidePanel} from '../components/show/IssueSidePanel'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import type {AppPayload} from '../types/app-payload'
import type {SubIssueSidePanelItem} from '@github-ui/sub-issues/sub-issue-types'

const PageQuery = graphql`
  query IssueDashboardKnownViewPageQuery(
    $query: String = "state:open archived:false assignee:@me sort:updated-desc"
    $first: Int = 25
    $labelPageSize: Int = 20
    $skip: Int = null
  ) {
    ...ListQuery
      @arguments(query: $query, first: $first, labelPageSize: $labelPageSize, skip: $skip, fetchRepository: true)
  }
`

export const IssueDashboardKnownViewPage: EntryPointComponent<
  {
    pageQuery: IssueDashboardKnownViewPageQuery
    customViewsQuery: SavedViewsQuery
  },
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
  const {queryRef: pageQueryRef, loadQuery: loadQuery} = useEntryPointsLoader(pageQuery, PageQuery)
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

  if (!pageQueryRef) return null
  if (!customViewsRef) return null

  return (
    <>
      <IssueDashboardKnownViewPageContent
        id={id}
        pageQueryRef={pageQueryRef}
        loadQuery={loadQuery}
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

function IssueDashboardKnownViewPageContent({
  id,
  pageQueryRef,
  loadQuery,
  savedViewsQueryRef,
  onSidePanelNavigate,
}: {
  id?: string
  pageQueryRef: PreloadedQuery<IssueDashboardKnownViewPageQuery>
  savedViewsQueryRef: PreloadedQuery<SavedViewsQuery>
  loadQuery: (
    variables: IssueDashboardKnownViewPageQuery$variables,
    options?: UseQueryLoaderLoadQueryOptions | undefined,
  ) => void
  onSidePanelNavigate?: (issue: ItemIdentifier) => void
}) {
  const data = usePreloadedQuery<IssueDashboardKnownViewPageQuery>(PageQuery, pageQueryRef)
  const currentViewNode = useLazyLoadQuery<ClientSideRelayDataGeneratorViewQuery>(
    currentView,
    {id},
    {fetchPolicy: 'store-only'},
  )

  return (
    <AnalyticsWrapper category="Issues Dashboard">
      <ThreePanesLayout
        leftPaneWidth={'small'}
        leftPane={{
          element: <Sidebar customViewsRef={savedViewsQueryRef} isFullHeight />,
          ariaLabel: LABELS.viewSidebarPaneAriaLabel,
        }}
        middlePane={
          currentViewNode.node ? (
            <List
              fetchedView={currentViewNode.node}
              search={data}
              fetchedRepository={null}
              loadSearchQuery={loadQuery}
              onSidePanelNavigate={onSidePanelNavigate}
              showSsoBanner
            />
          ) : undefined
        }
      />
      <MobileNavigation customViewsRef={savedViewsQueryRef} />
    </AnalyticsWrapper>
  )
}

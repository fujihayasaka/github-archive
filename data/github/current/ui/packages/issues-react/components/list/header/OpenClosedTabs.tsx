import {clsx} from 'clsx'
import {ListViewSectionFilterLink} from '@github-ui/list-view/ListViewSectionFilterLink'
import type {ScopedRepository} from '@github-ui/list-view-items-issues-prs/Query'
import {checkIfStateReasonPresent, getQuery} from '@github-ui/list-view-items-issues-prs/Query'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {testIdProps} from '@github-ui/test-id-props'
import {useIsPlatform} from '@github-ui/use-is-platform'
import {Suspense, useCallback, useMemo} from 'react'
import {graphql, useLazyLoadQuery} from 'react-relay'

import {QUERIES} from '@github-ui/query-builder/constants/queries'
import {useQueryContext} from '../../../contexts/QueryContext'
import {kFormatter} from '../../../utils/descriptions'
import {
  getClosedHref,
  getOpenHref,
  isClosedQuery,
  isOpenQuery,
  isNegatedClosedQuery,
  isNegatedOpenQuery,
} from '../../../utils/urls'
import type {OpenClosedTabsQuery} from './__generated__/OpenClosedTabsQuery.graphql'
import styles from '../ListItems.module.css'

type OpenClosedProps = {
  applySectionFilter?: (href: string, url: string) => void
  scopedRepository?: ScopedRepository
}

const SuspendedFilterLinks = ({
  isClosedTabActive,
  isOpenTabActive,
}: {
  isClosedTabActive: boolean
  isOpenTabActive: boolean
}) => (
  <div className={`${clsx(styles.tabsContainer, styles.loading)}`}>
    <ListViewSectionFilterLink key="open" title="Open" isSelected={isOpenTabActive} isLoading href={''} />
    <ListViewSectionFilterLink key="closed" title="Closed" isSelected={isClosedTabActive} isLoading href={''} />
  </div>
)

export function OpenClosedTabs(props: OpenClosedProps) {
  const {activeSearchQuery} = useQueryContext()

  const isOpen = isOpenQuery(activeSearchQuery)
  const isClosed = isClosedQuery(activeSearchQuery)
  const isNegatedOpen = isNegatedOpenQuery(activeSearchQuery)
  const isNegatedClosed = isNegatedClosedQuery(activeSearchQuery)

  const isOpenTabActive = (isOpen && !isNegatedOpen) || isNegatedClosed
  const isClosedTabActive = (isClosed && !isNegatedClosed) || isNegatedOpen

  return (
    <Suspense
      fallback={<SuspendedFilterLinks isOpenTabActive={isOpenTabActive} isClosedTabActive={isClosedTabActive} />}
    >
      <OpenClosedTabsInternal {...props} />
    </Suspense>
  )
}

function OpenClosedTabsInternal({applySectionFilter, scopedRepository}: OpenClosedProps) {
  const {activeSearchQuery} = useQueryContext()
  const urlPath = ssrSafeLocation.pathname

  const openHref = useMemo(() => getOpenHref(activeSearchQuery), [activeSearchQuery])
  const openQueryStr = openHref ? `?q=${encodeURIComponent(openHref)}` : ''
  const openHrefUrl = `${urlPath}${openQueryStr}`

  const closedHref = useMemo(() => getClosedHref(activeSearchQuery), [activeSearchQuery])
  const closedHrefUrl = closedHref ? `${urlPath}?q=${encodeURIComponent(closedHref)}` : urlPath
  const isMac = useIsPlatform(['mac'])
  const onClick = useCallback(
    (event: React.MouseEvent<HTMLAnchorElement>, isOpen: boolean) => {
      if (!activeSearchQuery || !applySectionFilter) return

      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      const isMetaKey = isMac ? event.metaKey : event.ctrlKey
      if (isMetaKey) {
        return
      }

      event.preventDefault()
      const href = event.currentTarget.href
      applySectionFilter(isOpen ? openHref || QUERIES.defaultRepoLevelOpen : closedHref, href)
    },
    [activeSearchQuery, applySectionFilter, closedHref, isMac, openHref],
  )

  const isOpen = isOpenQuery(activeSearchQuery)
  const isClosed = isClosedQuery(activeSearchQuery)
  const isNegatedOpen = isNegatedOpenQuery(activeSearchQuery)
  const isNegatedClosed = isNegatedClosedQuery(activeSearchQuery)

  const isOpenTabActive = (isOpen && !isNegatedOpen) || isNegatedClosed
  const isClosedTabActive = (isClosed && !isNegatedClosed) || isNegatedOpen

  const query = useMemo(() => {
    let searchQuery = checkIfStateReasonPresent(openHref) ? closedHref : openHref
    searchQuery = getQuery(searchQuery, scopedRepository)

    if (openHref) return searchQuery

    // When there is no openHref (when the page is loaded for the first time), we need to add is:issue to the query
    // to make sure we only count issues
    return `is:issue ${searchQuery}`
  }, [closedHref, openHref, scopedRepository])

  const data = useLazyLoadQuery<OpenClosedTabsQuery>(
    graphql`
      query OpenClosedTabsQuery(
        $query: String = "archived:false assignee:@me sort:updated-desc"
        $name: String!
        $owner: String!
      ) {
        repository(owner: $owner, name: $name) {
          search(first: 0, query: $query, type: ISSUE_ADVANCED, aggregations: true) {
            closedIssueCount
            openIssueCount
          }
        }
      }
    `,
    {query, owner: scopedRepository!.owner, name: scopedRepository!.name},
    {fetchPolicy: 'store-or-network'},
  )

  const closedIssueCount = data.repository?.search?.closedIssueCount || 0
  const openIssueCount = data.repository?.search?.openIssueCount || 0

  return (
    <div {...testIdProps('list-view-section-filters')}>
      <ul className={`list-style-none ${clsx(styles.tabsContainer)}`}>
        <li key={`section-filter-0`} {...testIdProps(`list-view-section-filter-0`)}>
          <ListViewSectionFilterLink
            key="open"
            title="Open"
            isSelected={isOpenTabActive && !isClosedTabActive}
            count={kFormatter(openIssueCount)}
            href={openHrefUrl}
            onClick={e => onClick(e, true)}
          />
        </li>
        <li key={`section-filter-1`} {...testIdProps(`list-view-section-filter-1`)}>
          <ListViewSectionFilterLink
            key="closed"
            title="Closed"
            isSelected={isClosedTabActive && !isOpenTabActive}
            count={kFormatter(closedIssueCount)}
            href={closedHrefUrl}
            onClick={e => onClick(e, false)}
          />
        </li>
      </ul>
    </div>
  )
}

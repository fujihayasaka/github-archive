import {ListViewSectionFilterLink} from '@github-ui/list-view/ListViewSectionFilterLink'
import {useFragment} from 'react-relay'
import {clsx} from 'clsx'
import {graphql} from 'relay-runtime'
import type {OpenClosedMilestones$key} from './__generated__/OpenClosedMilestones.graphql'
import {IS_BROWSER, ssrSafeWindow} from '@github-ui/ssr-utils'
import {useIsPlatform} from '@github-ui/use-is-platform'
import {useNavigate, useSearchParams} from '@github-ui/use-navigate'
import styles from './RepositoryMilestone.module.css'
import {useCallback} from 'react'

export function OpenClosedMilestones({repository}: {repository: OpenClosedMilestones$key}) {
  const data = useFragment(
    graphql`
      fragment OpenClosedMilestones on Repository {
        open: milestones(first: 0, states: OPEN) {
          totalCount
        }
        closed: milestones(first: 0, states: CLOSED) {
          totalCount
        }
      }
    `,
    repository,
  )
  const openIssueCount = Math.abs(data?.open?.totalCount || 0).toLocaleString()
  const closedIssueCount = Math.abs(data?.closed?.totalCount || 0).toLocaleString()
  let openHrefUrl = ''
  if (ssrSafeWindow) {
    openHrefUrl = ssrSafeWindow.location.pathname
  }
  const closedHrefUrl = `${openHrefUrl}?state=closed`
  const [searchParams] = useSearchParams()
  const searchString = searchParams.get('state')
  const isMac = useIsPlatform(['mac'])
  const navigate = useNavigate()
  const onClick = useCallback(
    (event: React.MouseEvent<HTMLAnchorElement>, isOpen: boolean) => {
      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      const isMetaKey = isMac ? event.metaKey : event.ctrlKey
      if (isMetaKey || !ssrSafeWindow) {
        return
      }

      event.preventDefault()
      const params = new URLSearchParams(searchParams)
      if (isOpen) {
        params.delete('state')
      } else {
        params.set('state', 'closed')
      }
      const href = `${ssrSafeWindow.location.pathname}?${params.toString()}`

      navigate(href)
    },
    [isMac, navigate, searchParams],
  )
  return (
    <div>
      <ul className={`list-style-none ${clsx(styles.tabsContainer)}`}>
        <li key={`section-filter-0`}>
          <ListViewSectionFilterLink
            key="open"
            title="Open"
            isSelected={IS_BROWSER && searchString !== 'closed'}
            count={openIssueCount}
            href={openHrefUrl}
            onClick={e => onClick(e, true)}
            data-testid="open-milestone-tab"
          />
        </li>
        <li key={`section-filter-1`}>
          <ListViewSectionFilterLink
            key="closed"
            title="Closed"
            isSelected={IS_BROWSER && searchString === 'closed'}
            count={closedIssueCount}
            href={closedHrefUrl}
            onClick={e => onClick(e, false)}
            data-testid="closed-milestone-tab"
          />
        </li>
      </ul>
    </div>
  )
}

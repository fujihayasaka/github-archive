import {ListViewSectionFilterLink} from '@github-ui/list-view/ListViewSectionFilterLink'
import {useFragment} from 'react-relay'
import {clsx} from 'clsx'
import {graphql} from 'relay-runtime'
import type {OpenClosedMilestoneIssues$key} from './__generated__/OpenClosedMilestoneIssues.graphql'
import {IS_BROWSER, ssrSafeWindow} from '@github-ui/ssr-utils'
import {useIsPlatform} from '@github-ui/use-is-platform'
import {useNavigate, useSearchParams} from '@github-ui/use-navigate'
import styles from './RepositoryMilestone.module.css'
import {useCallback} from 'react'

export function OpenClosedMilestoneIssues({milestoneRef}: {milestoneRef: OpenClosedMilestoneIssues$key}) {
  const data = useFragment(
    graphql`
      fragment OpenClosedMilestoneIssues on Milestone {
        closedIssues: issues(first: 0, states: CLOSED) {
          totalCount
        }
        openIssues: issues(first: 0, states: OPEN) {
          totalCount
        }
      }
    `,
    milestoneRef,
  )
  const openIssueCount = Math.abs(data.openIssues?.totalCount || 0).toLocaleString()
  const closedIssueCount = Math.abs(data.closedIssues?.totalCount || 0).toLocaleString()
  let openHrefUrl = ''
  if (ssrSafeWindow) {
    openHrefUrl = ssrSafeWindow.location.pathname
  }
  const closedHrefUrl = `${openHrefUrl}?closed=1`
  const [searchParams] = useSearchParams()
  const searchString = searchParams.get('closed')
  const isMac = useIsPlatform(['mac'])
  const navigate = useNavigate()
  const onClick = useCallback(
    (event: React.MouseEvent<HTMLAnchorElement>, isOpen: boolean) => {
      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      const isMetaKey = isMac ? event.metaKey : event.ctrlKey
      if (isMetaKey) {
        return
      }

      event.preventDefault()
      const href = isOpen ? openHrefUrl : closedHrefUrl
      navigate(href)
    },
    [closedHrefUrl, isMac, navigate, openHrefUrl],
  )
  return (
    <div>
      <ul className={`list-style-none ${clsx(styles.tabsContainer)}`}>
        <li key={`section-filter-0`}>
          <ListViewSectionFilterLink
            key="open"
            title="Open"
            isSelected={IS_BROWSER && searchString !== '1'}
            count={openIssueCount}
            href={openHrefUrl}
            onClick={e => onClick(e, true)}
          />
        </li>
        <li key={`section-filter-1`}>
          <ListViewSectionFilterLink
            key="closed"
            title="Closed"
            isSelected={IS_BROWSER && searchString === '1'}
            count={closedIssueCount}
            href={closedHrefUrl}
            onClick={e => onClick(e, false)}
          />
        </li>
      </ul>
    </div>
  )
}

import {UnderlineNav, Stack} from '@primer/react'
import {useRouteQuery} from '@github-ui/react-core/future/use-route-query'
import {reactSandboxFutureDashboardIssuesRoute} from '../routes/dashboard-issues-route'
import {reactSandboxFutureDashboardRoute} from '../routes/dashboard-route'
import {Link, useSearchParams} from 'react-router-dom'
import {IssueTable} from '../components/IssueTable'

export function Issues() {
  const {
    data: {open: openIssueCount, closed: closedIssueCount},
  } = useRouteQuery(reactSandboxFutureDashboardIssuesRoute, 'mainQuery')
  const {data: deferredIssues, isPending: isPendingIssues} = useRouteQuery(
    reactSandboxFutureDashboardIssuesRoute,
    'deferredIssues',
  )
  const {
    data: {user},
  } = useRouteQuery(reactSandboxFutureDashboardRoute, 'mainQuery')
  const issues = deferredIssues?.issues || []
  const [search] = useSearchParams()

  return (
    <Stack>
      <h3>Issues for {user}</h3>
      <UnderlineNav aria-label="Issues">
        <UnderlineNav.Item
          as={Link}
          to={reactSandboxFutureDashboardIssuesRoute.generatePath({}, {search: {state: 'open', ignore: 'true'}})}
          aria-current={search.get('state') !== 'closed' ? 'page' : undefined}
          counter={openIssueCount}
        >
          Open Issues
        </UnderlineNav.Item>
        <UnderlineNav.Item
          as={Link}
          to={reactSandboxFutureDashboardIssuesRoute.generatePath({}, {search: {state: 'closed', ignore: 'true'}})}
          aria-current={search.get('state') === 'closed' ? 'page' : undefined}
          counter={closedIssueCount}
        >
          Closed Issues
        </UnderlineNav.Item>
      </UnderlineNav>

      <IssueTable issues={issues} isPending={isPendingIssues} />
    </Stack>
  )
}

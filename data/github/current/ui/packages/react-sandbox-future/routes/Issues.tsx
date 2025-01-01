import {useRouteQuery} from '@github-ui/react-core/future/use-route-query'
import {Stack, UnderlineNav} from '@primer/react'
import {Link, useSearchParams} from 'react-router-dom'

import {IssueTable} from '../components/IssueTable'
import {reactSandboxFutureDashboardIssuesRoute} from '../routes/dashboard-issues-route'
import {reactSandboxFutureDashboardRoute} from '../routes/dashboard-route'

export function Issues() {
  const {
    data: {open: openIssueCount, closed: closedIssueCount},
  } = useRouteQuery(reactSandboxFutureDashboardIssuesRoute, 'mainQuery')
  const {
    data: deferredIssues,
    isPending: isPendingIssues,
    isError: isIssuesError,
    refetch: refetchIssues,
  } = useRouteQuery(reactSandboxFutureDashboardIssuesRoute, 'deferredIssues')
  const {
    data: {user},
  } = useRouteQuery(reactSandboxFutureDashboardRoute, 'mainQuery')
  const issues = deferredIssues?.issues || []
  const [search] = useSearchParams()

  return (
    <Stack data-testid="issues-nav">
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

      <IssueTable issues={issues} isPending={isPendingIssues} isError={isIssuesError} onRetry={() => refetchIssues()} />
    </Stack>
  )
}

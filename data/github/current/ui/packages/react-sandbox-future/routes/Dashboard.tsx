import {Stack, UnderlineNav} from '@primer/react'
import {useRouteQuery} from '@github-ui/react-core/future/use-route-query'
import {reactSandboxFutureDashboardRoute} from './dashboard-route'
import {Link, Outlet, useMatch} from 'react-router-dom'
import {reactSandboxFutureDashboardIssuesRoute} from './dashboard-issues-route'
import {reactSandboxFutureDashboardPullsRoute} from './dashboard-pulls-route'

export function ReactSandboxFutureDashboard() {
  const {
    data: {user},
  } = useRouteQuery(reactSandboxFutureDashboardRoute, 'mainQuery')

  const {data: deferredData} = useRouteQuery(reactSandboxFutureDashboardRoute, 'deferredPayload')

  const openIssueCount = deferredData?.tabCounts.openIssues
  const openPullCount = deferredData?.tabCounts.openPulls

  const isIssues = useMatch({path: reactSandboxFutureDashboardIssuesRoute.generatePath({}), end: true})
  const isPulls = useMatch({path: reactSandboxFutureDashboardPullsRoute.generatePath({}), end: true})

  return (
    <Stack padding="normal">
      <h2 data-hpc>Dashboard for @{user}</h2>

      <UnderlineNav aria-label="Dashboard">
        <UnderlineNav.Item
          as={Link}
          to={reactSandboxFutureDashboardIssuesRoute.generatePath({})}
          aria-current={isIssues ? 'page' : undefined}
          counter={openIssueCount}
        >
          Issues
        </UnderlineNav.Item>
        <UnderlineNav.Item
          as={Link}
          to={reactSandboxFutureDashboardPullsRoute.generatePath({})}
          aria-current={isPulls ? 'page' : undefined}
          counter={openPullCount}
        >
          Pulls
        </UnderlineNav.Item>
      </UnderlineNav>

      <Outlet />
    </Stack>
  )
}

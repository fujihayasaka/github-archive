import {UnderlineNav, Stack} from '@primer/react'
import {useRouteQuery} from '@github-ui/react-core/future/use-route-query'
import {reactSandboxFutureDashboardPullsRoute} from '../routes/dashboard-pulls-route'
import {reactSandboxFutureDashboardRoute} from '../routes/dashboard-route'
import {Link, useSearchParams} from 'react-router-dom'
import {IssueTable} from '../components/IssueTable'

export function Pulls() {
  const {
    data: {open: openPullCount, closed: closedPullCount},
  } = useRouteQuery(reactSandboxFutureDashboardPullsRoute, 'mainQuery')
  const {data: deferredPulls, isPending: isPendingPulls} = useRouteQuery(
    reactSandboxFutureDashboardPullsRoute,
    'deferredPulls',
  )
  const {
    data: {user},
  } = useRouteQuery(reactSandboxFutureDashboardRoute, 'mainQuery')
  const pulls = deferredPulls?.pulls || []
  const [search] = useSearchParams()

  return (
    <Stack>
      <h3>Pulls for {user}</h3>
      <UnderlineNav aria-label="Pulls">
        <UnderlineNav.Item
          as={Link}
          to={reactSandboxFutureDashboardPullsRoute.generatePath({}, {search: {state: 'open', ignore: 'true'}})}
          aria-current={search.get('state') === 'closed' ? undefined : 'page'}
          counter={openPullCount}
        >
          Open Pulls
        </UnderlineNav.Item>
        <UnderlineNav.Item
          as={Link}
          to={reactSandboxFutureDashboardPullsRoute.generatePath({}, {search: {state: 'closed', ignore: 'true'}})}
          aria-current={search.get('state') === 'closed' ? 'page' : undefined}
          counter={closedPullCount}
        >
          Closed Pulls
        </UnderlineNav.Item>
      </UnderlineNav>

      <IssueTable issues={pulls} isPending={isPendingPulls} />
    </Stack>
  )
}

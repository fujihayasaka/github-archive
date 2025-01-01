import {useRouteQuery} from '@github-ui/react-core/future/use-route-query'

import {reactSandboxFutureDashboardDiscussionsRoute} from './dashboard-discussions-route'
import {reactSandboxFutureDashboardRoute} from './dashboard-route'

export function Discussions() {
  const {
    data: {open: openIssueCount, closed: closedIssueCount},
  } = useRouteQuery(reactSandboxFutureDashboardDiscussionsRoute, 'mainQuery')
  const {
    data: {user},
  } = useRouteQuery(reactSandboxFutureDashboardRoute, 'mainQuery')
  return (
    <div>
      <p>Discussions for {user}</p>
      <p>Open Discussions: {openIssueCount}</p>
      <p>Closed Discussions: {closedIssueCount}</p>
    </div>
  )
}

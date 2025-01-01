import {Outlet} from 'react-router-dom'
import {LayoutComponent} from '../App'
import {pullRequestsLayoutRoute} from './layout-route'
import {useRouteQuery} from '@github-ui/react-core/future/use-route-query'

export function LayoutEntrypoint() {
  const {
    data: {pullRequest, bannersData, repository, urls, user, aliveChannel},
  } = useRouteQuery(pullRequestsLayoutRoute, 'mainQuery')
  return (
    <LayoutComponent
      aliveChannel={aliveChannel}
      pullRequest={pullRequest}
      bannersData={bannersData}
      repository={repository}
      urls={urls}
      user={user}
    >
      <Outlet />
    </LayoutComponent>
  )
}

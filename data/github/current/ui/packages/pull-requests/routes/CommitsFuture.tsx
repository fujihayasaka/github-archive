import {useRouteQuery} from '@github-ui/react-core/future/use-route-query'
import {CommitsComponent} from './Commits'
import {pullRequestsCommitsRoute} from './commits-route'
import {pullRequestsLayoutRoute} from './layout-route'

export function CommitsEntrypointFuture() {
  const {
    data: {pullRequest, aliveChannel, repository},
  } = useRouteQuery(pullRequestsLayoutRoute, 'mainQuery')
  const {
    data: {metadata, commitGroups, timeOutMessage, truncated},
  } = useRouteQuery(pullRequestsCommitsRoute, 'mainQuery')

  return (
    <CommitsComponent
      aliveChannel={aliveChannel}
      commitGroups={commitGroups}
      metadata={metadata}
      pullRequest={pullRequest}
      repository={repository}
      timeOutMessage={timeOutMessage}
      truncated={truncated}
    />
  )
}

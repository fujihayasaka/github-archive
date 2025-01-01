import {useRouteQuery} from '@github-ui/react-core/future/use-route-query'
import {LayoutComponent} from '../App'
import {CommitsComponent} from './Commits'
import {pullRequestsCommitsRoute} from './commits-route'

export function CommitsEntrypointFuture() {
  const {
    data: {
      metadata,
      pullRequest,
      bannersData,
      repository,
      urls,
      user,
      commitGroups,
      timeOutMessage,
      truncated,
      aliveChannel,
    },
  } = useRouteQuery(pullRequestsCommitsRoute, 'mainQuery')

  return (
    <LayoutComponent
      aliveChannel={aliveChannel}
      pullRequest={pullRequest}
      bannersData={bannersData}
      repository={repository}
      urls={urls}
      user={user}
    >
      <CommitsComponent
        aliveChannel={aliveChannel}
        commitGroups={commitGroups}
        metadata={metadata}
        pullRequest={pullRequest}
        repository={repository}
        timeOutMessage={timeOutMessage}
        truncated={truncated}
      />
    </LayoutComponent>
  )
}

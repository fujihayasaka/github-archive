import {prefetchTopRepositories} from '@github-ui/item-picker/RepositoryPicker'
import {useQuery} from '@github-ui/react-query'
import {useRelayEnvironment} from 'react-relay'

export function useTopReposQuery() {
  const environment = useRelayEnvironment()

  return useQuery({
    queryKey: ['copilot-immersive-top-repos', JSON.stringify(environment)],
    // eslint-disable-next-line @tanstack/query/no-void-query-fn
    queryFn: async () => {
      const topRepositoriesFirst = 10
      const hasIssuesEnabled = true
      return await prefetchTopRepositories(environment, topRepositoriesFirst, hasIssuesEnabled).toPromise()
    },
  })
}

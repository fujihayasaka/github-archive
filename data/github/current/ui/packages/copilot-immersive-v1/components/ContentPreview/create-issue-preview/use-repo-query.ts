import {prefetchCurrentRepository, RepositoryFragment} from '@github-ui/item-picker/RepositoryPicker'
import type {RepositoryPickerRepository$key} from '@github-ui/item-picker/RepositoryPickerRepository.graphql'
import {useQuery} from '@github-ui/react-query'
import {readInlineData, useRelayEnvironment} from 'react-relay'

export function useRepoQuery({owner, repo}: {owner?: string; repo?: string}) {
  const environment = useRelayEnvironment()

  return useQuery({
    queryKey: ['copilot-immersive-current-repo', JSON.stringify(environment), owner, repo],
    // eslint-disable-next-line @tanstack/query/no-void-query-fn
    queryFn: async () => {
      if (!owner || !repo) {
        return null
      }

      const data = await prefetchCurrentRepository(environment, owner, repo).toPromise()
      if (data?.repository != null) {
        // eslint-disable-next-line no-restricted-syntax
        return readInlineData<RepositoryPickerRepository$key>(RepositoryFragment, data.repository)
      }
    },
  })
}

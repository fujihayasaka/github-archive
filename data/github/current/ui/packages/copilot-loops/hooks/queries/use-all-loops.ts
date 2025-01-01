import {useQuery} from '@github-ui/react-query'
import {usePipesService} from '../../contexts/PipesServiceProvider'
import type {LoopVersion} from '../../service/pipes-storage'
import type {Pipeline} from '../../types/app'

export const ALL_LOOPS_QUERY_KEY = 'all-loops'

export function useAllLoops(version: LoopVersion = 'latest') {
  const service = usePipesService()

  return useQuery<Pipeline[]>({
    queryKey: [ALL_LOOPS_QUERY_KEY, version],
    queryFn: async () => {
      return await service.getAllLoops(version)
    },
    refetchOnMount: true,
  })
}

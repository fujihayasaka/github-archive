import {useQuery} from '@github-ui/react-query'
import {useParams} from 'react-router-dom'
import {usePipesService} from '../../contexts/PipesServiceProvider'
import {dummyPipelines} from '../../example-loops/dummy-pipelines'
import type {LoopVersion} from '../../service/pipes-storage'
import type {Pipeline} from '../../types/app'

export const LOOP_QUERY_KEY = 'loop'

export function useLoop(version: LoopVersion = 'draft') {
  const {loopID} = useParams()
  const service = usePipesService()

  return useQuery<Pipeline | null>({
    queryKey: [LOOP_QUERY_KEY, loopID, version],
    queryFn: async () => {
      if (!loopID) return null

      // Check dummy pipelines first
      const dummyLoop = dummyPipelines.find(p => p.id === loopID) ?? null
      if (dummyLoop) {
        return dummyLoop as Pipeline
      }

      return await service.getLoop(loopID, version)
    },
    enabled: !!loopID,
    refetchOnMount: true,
  })
}

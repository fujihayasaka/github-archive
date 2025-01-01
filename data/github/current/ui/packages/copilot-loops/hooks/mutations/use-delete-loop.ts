import {useMutation, useQueryClient} from '@github-ui/react-query'
import {usePipesService} from '../../contexts/PipesServiceProvider'
import {ALL_LOOPS_QUERY_KEY} from '../queries/use-all-loops'
import {LOOP_QUERY_KEY} from '../queries/use-loop'
import type {LoopOperationResult} from '../../service/pipes-storage'

export function useDeleteLoop() {
  const queryClient = useQueryClient()
  const loopsService = usePipesService()

  return useMutation<LoopOperationResult, Error, string>({
    mutationFn: async (loopID: string) => {
      return await loopsService.deleteLoop(loopID)
    },
    onSuccess: (result, loopID) => {
      if (!result.success) return

      // Remove the loop from all related caches
      queryClient.removeQueries({queryKey: [LOOP_QUERY_KEY, loopID]})

      // Refetch loops list to ensure the UI is up to date
      queryClient.invalidateQueries({queryKey: [ALL_LOOPS_QUERY_KEY]})
    },
  })
}

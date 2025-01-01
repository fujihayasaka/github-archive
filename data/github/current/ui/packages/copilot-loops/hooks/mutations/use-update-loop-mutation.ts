import {useMutation, useQueryClient} from '@github-ui/react-query'
import {usePipesService} from '../../contexts/PipesServiceProvider'
import {LOOP_QUERY_KEY} from '../queries/use-loop'
import {ALL_LOOPS_QUERY_KEY} from '../queries/use-all-loops'
import type {LoopOperationResult} from '../../service/pipes-storage'
import type {Pipeline} from '../../types/app'
import {isDummyPipeline} from '../../example-loops/dummy-pipelines'

/**
 * Hook for updating loops using the new abstracted interface
 * This hook updates the draft version of the loop
 */
export function useUpdateLoopMutation() {
  const queryClient = useQueryClient()
  const pipesService = usePipesService()

  return useMutation<LoopOperationResult, Error, {loopID: string; updateFn: (loop: Pipeline | null) => Pipeline}>({
    mutationFn: async ({loopID, updateFn}) => {
      return await pipesService.updateLoop(loopID, updateFn)
    },
    onMutate: async ({loopID, updateFn}) => {
      // Cancel any outgoing refetches to avoid overwriting our optimistic update
      await queryClient.cancelQueries({queryKey: [LOOP_QUERY_KEY, loopID, 'draft']})

      // Snapshot the previous loop value for potential rollback
      const previousDraftLoop = queryClient.getQueryData<Pipeline>([LOOP_QUERY_KEY, loopID, 'draft'])

      // Optimistically update the cache with the new loop data
      if (previousDraftLoop && !isDummyPipeline(previousDraftLoop)) {
        const updatedLoop = updateFn(previousDraftLoop)
        queryClient.setQueryData([LOOP_QUERY_KEY, loopID, 'draft'], updatedLoop)
      }

      // Return context containing the previous loop data
      return {previousDraftLoop}
    },
    onSuccess: (result, {loopID}) => {
      if (!result.success) return

      // Invalidate related queries to ensure consistency
      queryClient.invalidateQueries({queryKey: [LOOP_QUERY_KEY, loopID, 'draft']})
      queryClient.invalidateQueries({queryKey: [ALL_LOOPS_QUERY_KEY, 'draft']})
    },
    onError: (error, {loopID}, context: unknown) => {
      // If the mutation fails, roll back to the previous state
      const typedContext = context as {previousDraftLoop?: Pipeline} | undefined
      if (typedContext?.previousDraftLoop) {
        queryClient.setQueryData([LOOP_QUERY_KEY, loopID, 'draft'], typedContext.previousDraftLoop)
      }
    },
  })
}

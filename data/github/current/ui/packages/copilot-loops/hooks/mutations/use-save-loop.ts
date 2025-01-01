import {useMutation, useQueryClient} from '@github-ui/react-query'
import {usePipesService} from '../../contexts/PipesServiceProvider'
import {LOOP_QUERY_KEY} from '../queries/use-loop'
import {ALL_LOOPS_QUERY_KEY} from '../queries/use-all-loops'
import type {LoopOperationResult} from '../../service/pipes-storage'
import type {Pipeline} from '../../types/app'

export function useSaveLoop() {
  const queryClient = useQueryClient()
  const pipesService = usePipesService()

  return useMutation<LoopOperationResult, Error, string>({
    mutationFn: async (loopID: string) => {
      return await pipesService.saveLoop(loopID)
    },
    onMutate: async (loopID: string) => {
      // Cancel any outgoing refetches to avoid overwriting our optimistic update
      await queryClient.cancelQueries({queryKey: [LOOP_QUERY_KEY, loopID]})

      // Snapshot the previous loop values for potential rollback
      const previousDraftLoop = queryClient.getQueryData<Pipeline>([LOOP_QUERY_KEY, loopID, 'draft'])
      const previousLatestLoop = queryClient.getQueryData<Pipeline>([LOOP_QUERY_KEY, loopID, 'latest'])

      // Optimistically update the cache - after save, both versions should return the same pipeline
      if (previousDraftLoop) {
        queryClient.setQueryData([LOOP_QUERY_KEY, loopID, 'latest'], previousDraftLoop)
        queryClient.setQueryData([LOOP_QUERY_KEY, loopID, 'draft'], previousDraftLoop)
      }

      // Return context containing the previous loop data
      return {previousDraftLoop, previousLatestLoop}
    },
    onSuccess: result => {
      if (!result.success || !result.loop) return

      const loopID = result.loop.id

      // Invalidate all related queries to ensure consistency
      queryClient.invalidateQueries({queryKey: [LOOP_QUERY_KEY, loopID]})
      queryClient.invalidateQueries({queryKey: [ALL_LOOPS_QUERY_KEY]})
    },
    onError: (error, loopID, context: unknown) => {
      // If the mutation fails, roll back to the previous state
      const typedContext = context as {previousDraftLoop?: Pipeline; previousLatestLoop?: Pipeline} | undefined
      if (typedContext?.previousDraftLoop) {
        queryClient.setQueryData([LOOP_QUERY_KEY, loopID, 'draft'], typedContext.previousDraftLoop)
      }
      if (typedContext?.previousLatestLoop) {
        queryClient.setQueryData([LOOP_QUERY_KEY, loopID, 'latest'], typedContext.previousLatestLoop)
      }
    },
  })
}

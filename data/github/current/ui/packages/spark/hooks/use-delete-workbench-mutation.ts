import {useMutation, useQueryClient} from '@github-ui/react-query'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'

import {workbenchesQueryOptions} from './use-workbenches-query'

export function useDeleteWorkbenchMutation() {
  const queryClient = useQueryClient()

  const {mutate: deleteWorkbench} = useMutation({
    mutationFn: async (id: string) => {
      const res = await verifiedFetchJSON(`/copilot/spark/workbench/${id}`, {method: 'DELETE'})
      if (!res.ok) throw new Error('Failed to delete')
      return id
    },
    onMutate: async workbenchId => {
      // Cancel any outgoing refetches (so they don't overwrite our optimistic update)
      await queryClient.cancelQueries({queryKey: workbenchesQueryOptions.queryKey})

      // Snapshot the previous value
      const previous = queryClient.getQueryData(workbenchesQueryOptions.queryKey)

      // Optimistically update to the new value
      queryClient.setQueryData(workbenchesQueryOptions.queryKey, data => {
        return data?.filter(w => w.id !== workbenchId)
      })

      // Return a context object with the snapshotted value
      return {previous}
    },
    // if the mutation fails, use the context returned from onMutate to roll back
    onError: (_, __, context) => {
      if (context?.previous) {
        queryClient.setQueryData(workbenchesQueryOptions.queryKey, context.previous)
      }
    },
    onSettled: () => {
      return queryClient.invalidateQueries({queryKey: workbenchesQueryOptions.queryKey})
    },
  })

  return {deleteWorkbench}
}

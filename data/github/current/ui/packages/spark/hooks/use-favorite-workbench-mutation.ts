import {useMutation, useQueryClient} from '@github-ui/react-query'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'

import {workbenchesQueryOptions} from './use-workbenches-query'

export function useFavoriteWorkbenchMutation() {
  const queryClient = useQueryClient()

  const {mutate: favoriteWorkbench} = useMutation({
    mutationFn: async (input: {id: string; favorite: boolean}) => {
      const res = await verifiedFetchJSON(`/spark/favorites/${input.id}`, {method: input.favorite ? 'POST' : 'DELETE'})
      if (!res.ok) throw new Error('Failed to favorite')
      return input.id
    },
    onMutate: async input => {
      // Cancel any outgoing refetches (so they don't overwrite our optimistic update)
      await queryClient.cancelQueries({queryKey: workbenchesQueryOptions.queryKey})

      // Snapshot the previous value
      const previous = queryClient.getQueryData(workbenchesQueryOptions.queryKey)

      // Optimistically update to the new value
      queryClient.setQueryData(workbenchesQueryOptions.queryKey, data => {
        return data?.map(w => (w.id === input.id ? {...w, favorite: input.favorite} : w))
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

  return {favoriteWorkbench}
}

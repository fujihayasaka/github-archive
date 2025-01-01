import {reactFetchJSON} from '@github-ui/verified-fetch'
import {useMutation, useQueryClient} from '@github-ui/react-query'
import {fileViewedSettingsKey} from '../page-data/payloads/file-viewed-settings'

type RequestBody = {
  path: string
  viewed?: 'viewed'
  _method?: 'delete'
}
type Callbacks = {
  onSuccess: () => void
  onError: (e: Error) => void
}

export function useUpdateFileViewedStatusMutation(basePath: string, {onSuccess, onError}: Callbacks) {
  const apiURL = `${basePath}/file_review`

  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async ({viewedStatus, path}: {viewedStatus: boolean; path: string}) => {
      const body: RequestBody = {
        path,
        viewed: viewedStatus ? 'viewed' : undefined,
        _method: viewedStatus ? undefined : 'delete',
      }

      const result = await reactFetchJSON(`${apiURL}`, {
        method: viewedStatus ? 'POST' : 'DELETE',
        headers: {
          Accept: 'application/json',
        },
        body,
      })
      const json = await result.json()
      if (result.ok) return json
      const errorMessage = json.error || 'Unknown error occurred'
      throw new Error(errorMessage, {cause: result.status})
    },
    onMutate: async (variables: {viewedStatus: boolean; path: string}) => {
      queryClient.setQueryData(fileViewedSettingsKey(variables.path, basePath), () => {
        return variables.viewedStatus
      })
    },
    onSuccess: () => {
      onSuccess()
    },
    onError: (e: Error) => {
      onError(e)
    },
  })
}

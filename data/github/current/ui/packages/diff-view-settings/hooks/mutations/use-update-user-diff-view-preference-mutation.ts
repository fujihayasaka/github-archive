import {reactFetchJSON} from '@github-ui/verified-fetch'
import {useMutation, useQueryClient} from '@github-ui/react-query'
import type {
  CommentsPreference,
  DiffLineSpacing,
  SplitPreference,
  DiffViewSettings,
} from '../../page-data/payloads/diff-view-settings'
import {diffViewSettingsKey} from '../../page-data/payloads/diff-view-settings'
import {isLoggedIn} from '@github-ui/client-env'

type RequestBody = {
  commentsPreference?: CommentsPreference
  lineSpacing?: DiffLineSpacing
  diff?: SplitPreference
}
type Callbacks = {
  onSuccess: () => void
  onError: (e: Error) => void
}

export function useUpdateUserDiffViewPreferenceMutation({onSuccess, onError}: Callbacks) {
  const apiURL = `/users/diffview`

  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async ({
      commentsPreference,
      lineSpacing,
      splitPreference,
    }: {
      commentsPreference?: CommentsPreference
      lineSpacing?: DiffLineSpacing
      splitPreference?: SplitPreference
    }) => {
      // avoid making the request if the user is not logged in
      if (!isLoggedIn()) return

      let body: RequestBody = {}

      if (commentsPreference) body = {...body, commentsPreference}
      if (lineSpacing) body = {...body, lineSpacing}
      if (splitPreference) body = {...body, diff: splitPreference}

      const result = await reactFetchJSON(`${apiURL}`, {
        method: 'POST',
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
    onMutate: async (variables: {
      commentsPreference?: CommentsPreference
      lineSpacing?: DiffLineSpacing
      splitPreference?: SplitPreference
    }) => {
      queryClient.setQueryData(diffViewSettingsKey(), (old: DiffViewSettings) => {
        return {...old, ...variables}
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

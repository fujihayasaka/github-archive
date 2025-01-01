import {
  fetchWithErrorHandling,
  parseJSONWithBetterErrors,
  throwErrorsIfBadResponse,
} from '@github-ui/pull-request-page-data-tooling/fetch-error-handling'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {usePageDataUrl} from '@github-ui/pull-request-page-data-tooling/use-page-data-url'
import {useMutation, useQueryClient} from '@github-ui/react-query'
import {useMergeBoxPageDataQueryKey} from '../../page-data/loaders/use-merge-box-page-data'

type updateMergeBoxPreferenceInput = {
  preferenceName: string
  preference: string
}

type ValidPreferenceName = keyof typeof ValidPreferencesAndValues

const ValidPreferencesAndValues = {
  status_checks_grouping_preference: ['grouped_by_status', 'ungrouped'],
}

export function useUpdateMergeBoxUserPreferenceMutation({onError}: {onError: (error: Error) => void}) {
  const apiURL = usePageDataUrl(PageData.updateMergeBoxUserPreference)
  const mergeBoxQueryKey = useMergeBoxPageDataQueryKey()
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async (data: updateMergeBoxPreferenceInput) => {
      if (!data.preferenceName || !data.preference) {
        throw new Error('Preference name and value must be provided.')
      }

      if (!(data.preferenceName in ValidPreferencesAndValues)) {
        throw new Error('Invalid preference name.')
      }

      const validValues = ValidPreferencesAndValues[data.preferenceName as ValidPreferenceName]
      if (!validValues.includes(data.preference)) {
        throw new Error('Invalid preference value.')
      }

      const response = await fetchWithErrorHandling(apiURL, {
        method: 'POST',
        headers: {
          Accept: 'application/json',
        },
        body: data,
      })
      const json = await parseJSONWithBetterErrors(response)
      throwErrorsIfBadResponse(response, json)
      return json
    },
    onSuccess: () => {
      return queryClient.invalidateQueries({queryKey: mergeBoxQueryKey}, {cancelRefetch: false})
    },
    onError: (e: Error) => {
      onError(e)
    },
  })
}

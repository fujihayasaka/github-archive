import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {usePageDataUrl} from '@github-ui/pull-request-page-data-tooling/use-page-data-url'
import {useMutation} from '@github-ui/react-query'
import {fetchPoll} from '@github-ui/fetch-utils'
import {
  fetchWithErrorHandling,
  throwErrorsIfBadResponse,
  parseJSONWithBetterErrors,
} from '@github-ui/pull-request-page-data-tooling/fetch-error-handling'

type Input = {
  updateMethod: string
  expectedHeadOid: string
}
type Callbacks = {
  onSuccess: () => void
  onError: (e: Error) => void
}
export function useUpdatePullRequestBranchMutation({onSuccess, onError}: Callbacks) {
  const apiURL = usePageDataUrl(PageData.updatePullRequestBranch)

  return useMutation<Response, Error, Input>({
    mutationFn: async ({updateMethod, expectedHeadOid}) => {
      return fetchWithErrorHandling(apiURL, {
        method: 'POST',
        headers: {
          Accept: 'application/json',
        },
        body: {updateMethod, expectedHeadOid},
      })
    },
    onSuccess: async data => {
      const json = await parseJSONWithBetterErrors(data)

      if (!data.ok) {
        throwErrorsIfBadResponse(data, json)
      }

      const orchestrationResult = await (
        await fetchPoll(json.orchestration.url, {headers: {accept: 'application/json'}})
      ).json()

      if (orchestrationResult.orchestration.error_message) {
        throw new Error(orchestrationResult.orchestration.error_message)
      } else {
        onSuccess()
      }
    },
    onError: (e: Error) => {
      onError(e)
    },
  })
}

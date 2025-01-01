import {useMutation, type UseMutationResult} from '@github-ui/react-query'
import {fetchJson} from '../utils/fetch-json'

export type CloseAlertsRequest = {
  alertNumbers: number[]
  resolution: string
  dismissalComment: string
}

export type CloseAlertsResponse = {
  message: string
}

export function useCloseAlertsMutation(
  path: string,
): UseMutationResult<CloseAlertsResponse, Error, CloseAlertsRequest> {
  return useMutation({
    mutationFn: request => {
      return fetchJson(path, {
        method: 'post',
        body: {
          alert_numbers: request.alertNumbers,
          resolution: request.resolution,
          dismissal_comment: request.dismissalComment,
        },
      })
    },
  })
}

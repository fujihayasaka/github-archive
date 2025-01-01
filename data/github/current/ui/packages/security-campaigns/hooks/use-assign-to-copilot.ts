import {useMutation, type UseMutationResult} from '@github-ui/react-query'
import {fetchJson} from '../utils/fetch-json'

export type AssignToCopilotRequest = {
  alertNumbers: number[]
}

export type AssignToCopilotResponse = {
  message: string
}

export function useAssignToCopilot(
  path: string,
): UseMutationResult<AssignToCopilotResponse, Error, AssignToCopilotRequest> {
  return useMutation({
    mutationFn: request => {
      return fetchJson(path, {
        method: 'post',
        body: {
          alert_numbers: request.alertNumbers,
        },
      })
    },
  })
}

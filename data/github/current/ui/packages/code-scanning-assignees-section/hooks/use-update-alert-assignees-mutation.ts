import {codeScanningAlertAssigneesPath} from '@github-ui/paths'
import {useMutation, type UseMutationOptions, type UseMutationResult} from '@github-ui/react-query'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import type {Assignee} from '../types'

export type UpdateAlertAssigneesRequest = {
  assigneeIds: string[] | number[]
}

export type UpdateAlertAssigneesResponse = {
  assignees: Assignee[]
}

export function useUpdateAlertAssigneesMutation<TContext = unknown>(
  {
    owner,
    repo,
    alertNumber,
  }: {
    owner: string
    repo: string
    alertNumber: number
  },
  options?: Omit<
    UseMutationOptions<UpdateAlertAssigneesResponse, Error, UpdateAlertAssigneesRequest, TContext>,
    'mutationFn'
  >,
): UseMutationResult<UpdateAlertAssigneesResponse, Error, UpdateAlertAssigneesRequest, TContext> {
  return useMutation({
    mutationFn: async request => {
      const path = codeScanningAlertAssigneesPath({
        owner,
        repo,
        alertNumber,
      })
      const body = {
        assignee_ids: request.assigneeIds,
      }

      const response = await verifiedFetchJSON(path, {
        method: 'PATCH',
        body,
      })
      if (!response.ok) {
        throw new Error(`${response.status} on ${response.url}`)
      }
      return response.json()
    },
    ...options,
  })
}

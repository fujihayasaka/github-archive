import {useMutation, type UseMutationResult} from '@github-ui/react-query'
import {type JSONRequestInit, verifiedFetchJSON} from '@github-ui/verified-fetch'
import type {BranchData, BranchPickerData, SearchResult, PullRequestData, PullRequestPickerData} from '../types'

export interface UpdateAlertLinksRequest extends JSONRequestInit {
  linksToDelete: SearchResult[]
  linksToCreate: SearchResult[]
}

export type UpdatedAlertLink = {
  pull_request_number: number
  ref_name: string
}

export type UpdateAlertLinksResponse = {
  message: string
  data: {
    linked_branches: BranchData[]
    linked_pull_requests: PullRequestData[]
  }
}

const defaultErrorMessage = 'Something went wrong'

function pickerItemToRequestJson(item: PullRequestPickerData | BranchPickerData) {
  if (item.type === 'pull_request') {
    return {
      pull_request_number: item.number,
      ref_name: '',
    }
  }
  if (item.type === 'branch') {
    return {
      pull_request_number: 0,
      ref_name: item.name,
    }
  }
  throw new Error('Invalid item type')
}

export function useUpdateAlertLinksMutation(
  path: string,
): UseMutationResult<UpdateAlertLinksResponse, Error, UpdateAlertLinksRequest> {
  return useMutation({
    mutationKey: ['code-scanning-development-section', path],
    mutationFn: async request => {
      const response = await verifiedFetchJSON(path, {
        method: 'PATCH',
        body: {
          links_to_delete: request.linksToDelete.map(pickerItemToRequestJson),
          links_to_create: request.linksToCreate.map(pickerItemToRequestJson),
        },
      })
      if (!response.ok) {
        throw new Error(defaultErrorMessage)
      }
      return response.json()
    },
  })
}

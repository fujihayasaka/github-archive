import {useMutation, type UseMutationResult} from '@github-ui/react-query'
import {type JSONRequestInit, verifiedFetchJSON} from '@github-ui/verified-fetch'
import type {PullRequestPickerPullRequest$data} from '@github-ui/item-picker/PullRequestPickerPullRequest.graphql'
import type {BranchPickerRef$data} from '@github-ui/item-picker/BranchPickerRef.graphql'

export type LinkPayload = {
  pullRequestNumber: number
  refName: string
}

function linkPayloadToRequestJson(link: LinkPayload) {
  return {
    pull_request_number: link.pullRequestNumber,
    ref_name: link.refName,
  }
}

interface UpdateAlertLinksRequest extends JSONRequestInit {
  linksToDelete: LinkPayload[]
  linksToCreate: LinkPayload[]
}

// I'll need to get back all the links for the alert after the edits
export type UpdateAlertLinksResponse = {
  message: string
  currentLinks: LinkPayload[]
}

const defaultErrorMessage = 'Something went wrong'

export function pickerItemToLinkPayload(item: PullRequestPickerPullRequest$data | BranchPickerRef$data): LinkPayload {
  if (item.__typename === 'PullRequest') {
    return {
      pullRequestNumber: item.number,
      refName: '',
    }
  }
  if (item.__typename === 'Ref') {
    return {
      pullRequestNumber: 0,
      refName: item.name,
    }
  }
  throw new Error('Invalid item type')
}

export function useUpdateAlertLinksMutation(
  path: string,
): UseMutationResult<UpdateAlertLinksResponse, Error, UpdateAlertLinksRequest> {
  return useMutation({
    mutationFn: request => {
      return sendRequest(path, request)
    },
  })
}

async function sendRequest(path: string, request: UpdateAlertLinksRequest) {
  let response: Response

  try {
    response = await verifiedFetchJSON(path, {
      method: 'PATCH',
      body: {
        links_to_delete: request.linksToDelete.map(linkPayloadToRequestJson),
        links_to_create: request.linksToCreate.map(linkPayloadToRequestJson),
      },
    })
  } catch {
    throw new Error(defaultErrorMessage)
  }

  if (response.ok) {
    try {
      const data = (await response.json()).data
      return {
        message: data.message,
        currentLinks: data.current_links,
      } as UpdateAlertLinksResponse
    } catch {
      throw new Error(defaultErrorMessage)
    }
  }
  throw new Error(defaultErrorMessage)
}

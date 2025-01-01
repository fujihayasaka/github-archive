import type {PullRequest} from '../types/pull-request'
import {fetchJson} from '../utils/fetch-json'
import {useMutation, type UseMutationResult} from '@github-ui/react-query'

export type CreateBranchRequest = {
  name: string
  alertNumbers: number[]
  commitAutofixSuggestions: boolean
  createNewBranch: boolean
  createDraftPR: boolean
  commitMessage?: string
  extendedDescription?: string
}

export type CreateBranchResponse = {
  branchName: string
  pullRequest: PullRequest | null
  messages: string[]
}

export function useCreateBranchMutation(
  path: string,
): UseMutationResult<CreateBranchResponse, Error, CreateBranchRequest> {
  return useMutation({
    mutationFn: request => {
      return fetchJson(path, {
        defaultErrorMessage: 'Something went wrong',
        method: 'post',
        body: {
          name: request.name,
          alert_numbers: request.alertNumbers,
          commit_autofix_suggestions: request.commitAutofixSuggestions,
          create_new_branch: request.createNewBranch,
          create_draft_pr: request.createDraftPR,
          commit_message: request.commitMessage,
          extended_description: request.extendedDescription,
        },
      })
    },
  })
}

import {commitMutation, graphql} from 'react-relay'
import type {Environment} from 'relay-runtime'

import type {
  ConvertChecklistItemToSubIssueInput,
  createSubIssueFromChecklistItemMutation,
  createSubIssueFromChecklistItemMutation$data,
} from './__generated__/createSubIssueFromChecklistItemMutation.graphql'

type MutationProps = {
  environment: Environment
  input: ConvertChecklistItemToSubIssueInput
  onError?: (error: Error) => void
  onCompleted?: (response: createSubIssueFromChecklistItemMutation$data) => void
}
export function commitCreateSubIssueFromChecklistItemMutation({
  environment,
  input: {body, repositoryId, parentIssueId, position},
  onError,
  onCompleted,
}: MutationProps) {
  const inputHash: ConvertChecklistItemToSubIssueInput = {
    body,
    repositoryId,
    parentIssueId,
    position,
  }

  return commitMutation<createSubIssueFromChecklistItemMutation>(environment, {
    mutation: graphql`
      mutation createSubIssueFromChecklistItemMutation($input: ConvertChecklistItemToSubIssueInput!)
      @raw_response_type {
        convertChecklistItemToSubIssue(input: $input) {
          issue {
            id
            parent {
              id
              body
              bodyHTML(unfurlReferences: true, renderTasklistBlocks: true)
              ...SubIssuesList
            }
            ...SubIssuesListItem
          }
          errors {
            message
          }
        }
      }
    `,
    variables: {
      input: inputHash,
    },
    onError: error => onError && onError(error),
    onCompleted: response => onCompleted && onCompleted(response),
  })
}

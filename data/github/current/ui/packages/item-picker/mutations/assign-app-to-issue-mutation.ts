import {commitMutation, graphql} from 'react-relay'
import type {Environment} from 'relay-runtime'
import type {
  AssignAppToIssueInput,
  assignAppToIssueMutation,
  assignAppToIssueMutation$data,
} from './__generated__/assignAppToIssueMutation.graphql'

export function commitAssignAppToIssueMutation({
  environment,
  input,
  onError,
  onCompleted,
}: {
  environment: Environment
  input: AssignAppToIssueInput
  onError?: (error: Error) => void
  onCompleted?: (response: assignAppToIssueMutation$data) => void
}) {
  return commitMutation<assignAppToIssueMutation>(environment, {
    mutation: graphql`
      mutation assignAppToIssueMutation($input: AssignAppToIssueInput!) @raw_response_type {
        assignAppToIssue(input: $input) {
          issue {
            id
            assignees(first: 20) {
              nodes {
                # eslint-disable-next-line relay/must-colocate-fragment-spreads
                ...AssigneePickerAssignee
              }
            }
            participants(first: 10) {
              nodes {
                ...AssigneePickerAssignee
              }
            }
          }
        }
      }
    `,
    variables: {
      input,
    },
    onError: error => onError && onError(error),
    onCompleted: response => onCompleted && onCompleted(response),
  })
}

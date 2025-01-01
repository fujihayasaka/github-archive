import {commitMutation, graphql} from 'react-relay'
import type {Environment} from 'relay-runtime'
import type {
  DeleteMilestoneInput,
  deleteMilestoneMutation,
  deleteMilestoneMutation$data,
} from './__generated__/deleteMilestoneMutation.graphql'

export function commitDeleteMilestoneMutation({
  environment,
  input,
  onError,
  onCompleted,
}: {
  environment: Environment
  input: DeleteMilestoneInput
  onError?: (error: Error) => void
  onCompleted?: (response: deleteMilestoneMutation$data) => void
}) {
  return commitMutation<deleteMilestoneMutation>(environment, {
    mutation: graphql`
      mutation deleteMilestoneMutation($input: DeleteMilestoneInput!) @raw_response_type {
        deleteMilestone(input: $input) {
          milestone {
            id @deleteRecord
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

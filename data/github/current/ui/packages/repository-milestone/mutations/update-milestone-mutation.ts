import {commitMutation, graphql} from 'react-relay'
import type {Environment} from 'relay-runtime'
import type {
  MilestoneState,
  updateMilestoneMutation,
  updateMilestoneMutation$data,
} from './__generated__/updateMilestoneMutation.graphql'

export function commitUpdateMilestoneMutation({
  environment,
  input,
  onError,
  onCompleted,
}: {
  environment: Environment
  input: {state: MilestoneState; id: string}
  onError?: (error: Error) => void
  onCompleted?: (response: updateMilestoneMutation$data) => void
}) {
  return commitMutation<updateMilestoneMutation>(environment, {
    mutation: graphql`
      mutation updateMilestoneMutation($input: UpdateMilestoneInput!) @raw_response_type {
        updateMilestone(input: $input) {
          milestone {
            id
            closed
          }
        }
      }
    `,
    variables: {
      input,
    },
    onError: error => onError && onError(error),
    optimisticResponse: {
      updateMilestone: {
        milestone: {
          id: input.id,
          closed: input.state === 'CLOSED',
        },
      },
    },
    onCompleted: response => onCompleted && onCompleted(response),
  })
}

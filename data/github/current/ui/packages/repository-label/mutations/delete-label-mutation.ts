import {commitMutation, graphql} from 'react-relay'
import type {Environment} from 'relay-runtime'
import type {
  DeleteLabelInput,
  deleteLabelMutation$data,
  deleteLabelMutation,
} from './__generated__/deleteLabelMutation.graphql'

export function commitDeleteLabelMutation({
  environment,
  input,
  onError,
  onCompleted,
}: {
  environment: Environment
  input: DeleteLabelInput
  onError?: (error: Error) => void
  onCompleted?: (response: deleteLabelMutation$data) => void
}) {
  return commitMutation<deleteLabelMutation>(environment, {
    mutation: graphql`
      mutation deleteLabelMutation($input: DeleteLabelInput!) @raw_response_type {
        deleteLabel(input: $input) {
          clientMutationId
        }
      }
    `,
    variables: {
      input,
    },
    optimisticUpdater: store => {
      store.delete(input.id)
    },
    updater: store => {
      store.delete(input.id)
    },
    onError: error => onError?.(error),
    onCompleted: response => onCompleted?.(response),
  })
}

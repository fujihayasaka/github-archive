import {commitMutation, graphql} from 'react-relay'
import type {Environment} from 'relay-runtime'
import type {updateLabelMutation$data, updateLabelMutation} from './__generated__/updateLabelMutation.graphql'

export function commitUpdateLabelMutation({
  environment,
  input,
  onError,
  onCompleted,
}: {
  environment: Environment
  input: {
    id: string
    name: string
    description?: string
    color: string
  }
  onError?: (error: Error) => void
  onCompleted?: (response: updateLabelMutation$data) => void
}) {
  return commitMutation<updateLabelMutation>(environment, {
    mutation: graphql`
      mutation updateLabelMutation($input: UpdateLabelInput!) @raw_response_type {
        updateLabel(input: $input) {
          label {
            id
            name
            nameHTML
            description
            color
          }
        }
      }
    `,
    variables: {input},
    optimisticResponse: {
      updateLabel: {
        label: {
          id: input.id,
          name: input.name,
          nameHTML: input.name,
          description: input.description ?? null,
          color: input.color,
        },
      },
    },
    onError: error => onError?.(error),
    onCompleted: response => onCompleted?.(response),
  })
}

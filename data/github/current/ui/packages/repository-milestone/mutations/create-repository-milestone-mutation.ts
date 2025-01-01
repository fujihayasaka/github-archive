import {graphql} from 'react-relay'
import {commitMutation} from 'relay-runtime'

import type {
  createRepositoryMilestoneMutation,
  createRepositoryMilestoneMutation$data,
  createRepositoryMilestoneMutation$variables,
} from './__generated__/createRepositoryMilestoneMutation.graphql'
import type {Environment} from 'relay-runtime'

export type CreateRespositoryMilestoneResponse = createRepositoryMilestoneMutation$data['createMilestone']

export function commitCreateRepositoryMilestoneMutation({
  environment,
  input,
  onError,
  onCompleted,
}: {
  environment: Environment
  input: createRepositoryMilestoneMutation$variables['input']
  onError: (error: Error) => void
  onCompleted: (response: createRepositoryMilestoneMutation$data) => void
}) {
  return commitMutation<createRepositoryMilestoneMutation>(environment, {
    mutation: graphql`
      mutation createRepositoryMilestoneMutation($input: CreateMilestoneInput!) {
        createMilestone(input: $input) {
          milestone {
            number
          }
          errors {
            message
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

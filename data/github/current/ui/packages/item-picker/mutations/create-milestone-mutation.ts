import {commitMutation, graphql, type Environment} from 'react-relay'
import type {
  createMilestoneMutation,
  createMilestoneMutation$data,
} from './__generated__/createMilestoneMutation.graphql'

export function commitCreateMilestoneMutation({
  environment,
  input,
  onError,
  onCompleted,
}: {
  environment: Environment
  input: {
    repositoryId: string
    title: string
  }
  onError?: (error: Error) => void
  onCompleted?: (response: createMilestoneMutation$data) => void
}) {
  return commitMutation<createMilestoneMutation>(environment, {
    mutation: graphql`
      mutation createMilestoneMutation($input: CreateMilestoneInput!) @raw_response_type {
        createMilestone(input: $input) {
          milestone {
            closed
            closedAt
            dueOn
            id
            progressPercentage
            title
            url
          }
        }
      }
    `,
    variables: {input},
    onError: error => onError && onError(error),
    onCompleted: response => onCompleted && onCompleted(response),
  })
}

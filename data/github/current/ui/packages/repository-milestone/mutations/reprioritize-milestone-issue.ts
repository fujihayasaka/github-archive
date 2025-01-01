import {commitMutation, graphql} from 'react-relay'
import type {Environment} from 'relay-runtime'
import type {
  ReprioritizeMilestoneIssueInput,
  reprioritizeMilestoneIssueMutation,
  reprioritizeMilestoneIssueMutation$data,
} from './__generated__/reprioritizeMilestoneIssueMutation.graphql'

export function commitReprioritizeMilestoneIssueMutation({
  environment,
  input,
  onError,
  onCompleted,
}: {
  environment: Environment
  input: ReprioritizeMilestoneIssueInput
  onError?: (error: Error) => void
  onCompleted?: (response: reprioritizeMilestoneIssueMutation$data) => void
}) {
  return commitMutation<reprioritizeMilestoneIssueMutation>(environment, {
    mutation: graphql`
      mutation reprioritizeMilestoneIssueMutation($input: ReprioritizeMilestoneIssueInput!) @raw_response_type {
        reprioritizeMilestoneIssue(input: $input) {
          milestone {
            id
            updatedAt
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

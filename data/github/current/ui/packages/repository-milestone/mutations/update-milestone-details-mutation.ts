import {graphql} from 'react-relay'
import {commitMutation} from 'relay-runtime'

import type {
  updateMilestoneDetailsMutation,
  updateMilestoneDetailsMutation$data,
  updateMilestoneDetailsMutation$variables,
} from './__generated__/updateMilestoneDetailsMutation.graphql'
import type {Environment} from 'relay-runtime'

export type UpdateRespositoryMilestoneResponse = updateMilestoneDetailsMutation$data['updateMilestone']

export function commitUpdateMilestoneDetailsMutation({
  environment,
  input,
  onError,
  onCompleted,
}: {
  environment: Environment
  input: updateMilestoneDetailsMutation$variables['input']
  onError: (error: Error) => void
  onCompleted: (response: updateMilestoneDetailsMutation$data) => void
}) {
  return commitMutation<updateMilestoneDetailsMutation>(environment, {
    mutation: graphql`
      mutation updateMilestoneDetailsMutation($input: UpdateMilestoneInput!) {
        updateMilestone(input: $input) {
          milestone {
            ...MilestoneDetail
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

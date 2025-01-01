import {commitMutation, graphql} from 'react-relay'
import type {Environment} from 'relay-runtime'

import type {
  SubscriptionState,
  updateSubscriptionStateMutation,
} from './__generated__/updateSubscriptionStateMutation.graphql'

type UpdateSubscriptionStateMutationProps = {
  environment: Environment
  subscribableId: string
  state: SubscriptionState
  onCompleted?: () => void
  onError?: (error: Error) => void
}

export function updateSubscription({
  environment,
  subscribableId,
  state,
  onCompleted,
  onError,
}: UpdateSubscriptionStateMutationProps) {
  return commitMutation<updateSubscriptionStateMutation>(environment, {
    mutation: graphql`
      mutation updateSubscriptionStateMutation($input: UpdateSubscriptionInput!) @raw_response_type {
        updateSubscription(input: $input) {
          clientMutationId
        }
      }
    `,
    variables: {input: {subscribableId, state}},
    onError,
    onCompleted,
  })
}

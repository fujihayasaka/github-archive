import {commitMutation, graphql} from 'react-relay'
import type {Environment} from 'relay-runtime'

import type {
  updateIssueSubscriptionMutation,
  UpdateSubscriptionInput,
} from './__generated__/updateIssueSubscriptionMutation.graphql'

export function commitUpdateIssueSubscriptionMutation({
  environment,
  input,
  onCompleted,
  onError,
}: {
  environment: Environment
  input: UpdateSubscriptionInput
  onCompleted?: () => void
  onError?: (error: Error) => void
}) {
  return commitMutation<updateIssueSubscriptionMutation>(environment, {
    // Important: the name of this mutation is being used in app/platform/authorization/permission_check.rb (def emu_ownership_enforceable)
    // to decide whether EMU can subscribe to an issue in a public repo. If changing it, please change it there as well.
    mutation: graphql`
      mutation updateIssueSubscriptionMutation($input: UpdateSubscriptionInput!) @raw_response_type {
        updateSubscription(input: $input) {
          subscribable {
            ... on Issue {
              id
              viewerThreadSubscriptionFormAction
              viewerCustomSubscriptionEvents
            }
          }
        }
      }
    `,
    variables: {
      input,
    },
    optimisticResponse: {
      updateSubscription: {
        subscribable: {
          id: input.subscribableId,
          viewerThreadSubscriptionFormAction:
            input.state === 'SUBSCRIBED' || input.state === 'CUSTOM' ? 'UNSUBSCRIBE' : 'SUBSCRIBE',
          viewerCustomSubscriptionEvents: input.events,
          __typename: 'Issue',
        },
      },
    },
    onCompleted: () => onCompleted && onCompleted(),
    onError: error => onError && onError(error),
  })
}

import {commitMutation, graphql} from 'react-relay'
import type {Environment} from 'relay-runtime'

import type {markAsUnreadMutation} from './__generated__/markAsUnreadMutation.graphql'

type MarkAsUnreadMutationProps = {
  environment: Environment
  notificationId: string
  onError?: (error: Error) => void
}

export function markNotificationAsUnread({environment, notificationId, onError}: MarkAsUnreadMutationProps) {
  return commitMutation<markAsUnreadMutation>(environment, {
    mutation: graphql`
      mutation markAsUnreadMutation($input: MarkNotificationAsUnreadInput!) @raw_response_type {
        markNotificationAsUnread(input: $input) {
          success
          notificationThread {
            id
            isUnread
          }
        }
      }
    `,
    variables: {input: {id: notificationId}},
    optimisticResponse: {
      markNotificationAsUnread: {
        success: true,
        notificationThread: {
          id: notificationId,
          isUnread: true,
        },
      },
    },
    onError,
  })
}

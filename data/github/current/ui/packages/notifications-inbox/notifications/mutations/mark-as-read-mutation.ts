import {commitMutation, graphql} from 'react-relay'
import type {Environment} from 'relay-runtime'

import type {markAsReadMutation} from './__generated__/markAsReadMutation.graphql'

type MarkAsReadMutationProps = {
  environment: Environment
  notificationId: string
  onError?: (error: Error) => void
  onCompleted?: () => void
}

export function markNotificationAsRead({environment, notificationId, onError, onCompleted}: MarkAsReadMutationProps) {
  return commitMutation<markAsReadMutation>(environment, {
    mutation: graphql`
      mutation markAsReadMutation($input: MarkNotificationAsReadInput!) @raw_response_type {
        markNotificationAsRead(input: $input) {
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
      markNotificationAsRead: {
        success: true,
        notificationThread: {
          id: notificationId,
          isUnread: false,
        },
      },
    },
    onError,
    onCompleted: () => onCompleted && onCompleted(),
  })
}

import {commitMutation, graphql} from 'react-relay'
import type {Environment, RecordSourceSelectorProxy} from 'relay-runtime'

import type {
  markAllNotificationsMutation,
  NotificationStatus,
} from './__generated__/markAllNotificationsMutation.graphql'

type MarkAllNotificationsMutationProps = {
  environment: Environment
  state: NotificationStatus
  onError?: (error: Error) => void
  onCompleted?: () => void
  onUpdated?: (store: RecordSourceSelectorProxy) => void
}

export function markAllNotifications({
  environment,
  state,
  onError,
  onCompleted,
  onUpdated,
}: MarkAllNotificationsMutationProps) {
  return commitMutation<markAllNotificationsMutation>(environment, {
    mutation: graphql`
      mutation markAllNotificationsMutation($input: MarkAllNotificationsInput!) @raw_response_type {
        markAllNotifications(input: $input) {
          success
        }
      }
    `,
    variables: {input: {state, query: ''}},
    optimisticUpdater: store => onUpdated && onUpdated(store),
    updater: store => {
      onUpdated?.(store)
    },
    onError,
    onCompleted: () => onCompleted && onCompleted(),
  })
}

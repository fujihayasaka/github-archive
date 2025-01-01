import {commitMutation, graphql} from 'react-relay'
import type {Environment, RecordSourceSelectorProxy} from 'relay-runtime'

import type {markNotificationsAsUnreadMutation} from './__generated__/markNotificationsAsUnreadMutation.graphql'

type MarkNotificationsAsUnreadMutationProps = {
  environment: Environment
  notificationIds: Set<string>
  onError?: (error: Error) => void
  onCompleted?: () => void
}

export function updateNotificationsById(store: RecordSourceSelectorProxy, ids: Set<string>) {
  for (const id of ids) {
    const notification = store.get(id)
    if (!notification) return
    notification.setValue(true, 'isUnread')
  }
}

export function markNotificationsAsUnread({
  environment,
  notificationIds,
  onError,
  onCompleted,
}: MarkNotificationsAsUnreadMutationProps) {
  return commitMutation<markNotificationsAsUnreadMutation>(environment, {
    mutation: graphql`
      mutation markNotificationsAsUnreadMutation($input: MarkNotificationsAsUnreadInput!) @raw_response_type {
        markNotificationsAsUnread(input: $input) {
          success
        }
      }
    `,
    variables: {input: {ids: Array.from(notificationIds)}},
    optimisticUpdater: store => updateNotificationsById(store, notificationIds),
    updater: store => {
      updateNotificationsById(store, notificationIds)
    },
    onError,
    onCompleted: () => onCompleted && onCompleted(),
  })
}

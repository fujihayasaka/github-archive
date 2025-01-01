import {commitMutation, graphql} from 'react-relay'
import type {Environment, RecordSourceSelectorProxy} from 'relay-runtime'

import type {markNotificationsAsDoneMutation} from './__generated__/markNotificationsAsDoneMutation.graphql'

type MarkNotificationsAsDoneMutationProps = {
  environment: Environment
  notificationIds: Set<string>
  onError?: (error: Error) => void
  onCompleted?: () => void
}

export function updateNotificationsById(store: RecordSourceSelectorProxy, ids: Set<string>) {
  for (const id of ids) {
    const notification = store.get(id)
    if (!notification) return
    notification.setValue(true, 'isDone')
  }
}

export function markNotificationsAsDone({
  environment,
  notificationIds,
  onError,
  onCompleted,
}: MarkNotificationsAsDoneMutationProps) {
  return commitMutation<markNotificationsAsDoneMutation>(environment, {
    mutation: graphql`
      mutation markNotificationsAsDoneMutation($input: MarkNotificationsAsDoneInput!) @raw_response_type {
        markNotificationsAsDone(input: $input) {
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

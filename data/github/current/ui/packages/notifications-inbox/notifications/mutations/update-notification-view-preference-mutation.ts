import {commitMutation, graphql} from 'react-relay'
import type {Environment} from 'relay-runtime'

import type {NotificationViewPreference} from '../../types/notification'
import type {updateNotificationViewPreferenceMutation} from './__generated__/updateNotificationViewPreferenceMutation.graphql'

type UpdateNotificationViewPreferenceMutationProps = {
  environment: Environment
  viewPreference: NotificationViewPreference
  onError?: (error: Error) => void
  onCompleted?: () => void
}

export function updateNotificationViewPreference({
  environment,
  viewPreference,
  onError,
  onCompleted,
}: UpdateNotificationViewPreferenceMutationProps) {
  return commitMutation<updateNotificationViewPreferenceMutation>(environment, {
    mutation: graphql`
      mutation updateNotificationViewPreferenceMutation($input: UpdateNotificationViewPreferenceInput!)
      @raw_response_type {
        updateNotificationViewPreference(input: $input) {
          success
        }
      }
    `,
    variables: {input: {viewPreference}},
    onError,
    onCompleted: () => onCompleted && onCompleted(),
  })
}

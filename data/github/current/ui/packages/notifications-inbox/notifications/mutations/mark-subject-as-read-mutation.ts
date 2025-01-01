import {commitMutation, graphql} from 'react-relay'
import type {Environment} from 'relay-runtime'

import type {markSubjectAsReadMutation} from './__generated__/markSubjectAsReadMutation.graphql'

type MarkSubjectAsReadMutationProps = {
  environment: Environment
  subjectId: string
  onError?: (error: Error) => void
  onCompleted?: () => void
}

const markNotificationSubjectAsRead = ({
  environment,
  subjectId,
  onError,
  onCompleted,
}: MarkSubjectAsReadMutationProps) => {
  return commitMutation<markSubjectAsReadMutation>(environment, {
    mutation: graphql`
      mutation markSubjectAsReadMutation($input: MarkNotificationSubjectAsReadInput!) @raw_response_type {
        markNotificationSubjectAsRead(input: $input) {
          success
        }
      }
    `,
    variables: {input: {subjectId}},
    optimisticResponse: {
      markNotificationSubjectAsRead: {
        success: true,
      },
    },
    optimisticUpdater: store => {
      const subject = store.get(subjectId)
      if (subject) {
        subject.setValue(true, 'isReadByViewer')
      }
    },
    updater: store => {
      const subject = store.get(subjectId)
      if (subject) {
        subject.setValue(true, 'isReadByViewer')
      }
    },
    onError,
    onCompleted: () => onCompleted && onCompleted(),
  })
}

export default markNotificationSubjectAsRead

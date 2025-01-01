import {type Environment, commitMutation, graphql, ConnectionHandler} from 'react-relay'
import type {
  DeleteIssueTypeInput,
  deleteIssueTypeMutation,
  deleteIssueTypeMutation$data,
} from './__generated__/deleteIssueTypeMutation.graphql'

type deleteIssueTypeMutationParams = {
  environment: Environment
  input: DeleteIssueTypeInput
  connectionId?: string
  onError?: (error: Error) => void
  onCompleted?: (response: deleteIssueTypeMutation$data) => void
}

export function commitDeleteIssueTypeMutation({
  environment,
  input,
  connectionId,
  onError,
  onCompleted,
}: deleteIssueTypeMutationParams) {
  return commitMutation<deleteIssueTypeMutation>(environment, {
    mutation: graphql`
      mutation deleteIssueTypeMutation($input: DeleteIssueTypeInput!) @raw_response_type {
        deleteIssueType(input: $input) {
          deletedIssueTypeId
          errors {
            message
          }
        }
      }
    `,
    variables: {input},
    updater: store => {
      if (!connectionId) return
      const deletedIssueTypeId = store.getRootField('deleteIssueType')?.getValue('deletedIssueTypeId')
      const connection = store.get(connectionId)

      if (connection && deletedIssueTypeId) {
        ConnectionHandler.deleteNode(connection, deletedIssueTypeId)

        const currentCount = connection.getValue('totalCount')
        if (typeof currentCount === 'number') {
          connection.setValue(currentCount - 1, 'totalCount')
        }

        store.delete(deletedIssueTypeId)
      }
    },
    onError: error => onError && onError(error),
    onCompleted: response => onCompleted && onCompleted(response),
  })
}

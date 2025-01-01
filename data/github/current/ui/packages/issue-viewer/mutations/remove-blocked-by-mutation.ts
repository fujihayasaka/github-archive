import {commitMutation, ConnectionHandler, graphql} from 'react-relay'
import type {Environment} from 'relay-runtime'
import type {
  RemoveBlockedByInput,
  removeBlockedByMutation,
  removeBlockedByMutation$data,
} from './__generated__/removeBlockedByMutation.graphql'
import {BLOCKED_BY_LIST_ALL_RELAY_CONNECTION} from '../components/sections/relations-section/LazyRelationshipsBlockedByListView'
import {BLOCKING_LIST_ALL_RELAY_CONNECTION} from '../components/sections/relations-section/LazyRelationshipsBlockingListView'

export function removeBlockedByMutation({
  environment,
  input,
  onError,
  onCompleted,
}: {
  environment: Environment
  input: RemoveBlockedByInput
  onError?: (error: Error) => void
  onCompleted?: (response: removeBlockedByMutation$data) => void
}) {
  return commitMutation<removeBlockedByMutation>(environment, {
    mutation: graphql`
      mutation removeBlockedByMutation($input: RemoveBlockedByInput!) @raw_response_type {
        removeBlockedBy(input: $input) {
          issue {
            ...RelationshipsSectionFragment
          }
          blockingIssue {
            id
            number
            title
            repository {
              nameWithOwner
            }
            ...RelationshipsSectionFragment
          }
        }
      }
    `,
    variables: {
      input,
    },
    onError: error => onError && onError(error),
    onCompleted: response => onCompleted && onCompleted(response),
    updater: store => {
      store.get(input.issueId)?.getLinkedRecord('blockedBy', {first: 100})?.invalidateRecord()
      store.get(input.blockingIssueId)?.getLinkedRecord('blocking', {first: 100})?.invalidateRecord()

      const blockedByDataId = ConnectionHandler.getConnectionID(input.issueId, BLOCKED_BY_LIST_ALL_RELAY_CONNECTION)
      store.get(blockedByDataId)?.invalidateRecord()

      const blockingDataId = ConnectionHandler.getConnectionID(
        input.blockingIssueId,
        BLOCKING_LIST_ALL_RELAY_CONNECTION,
      )
      store.get(blockingDataId)?.invalidateRecord()
    },
  })
}

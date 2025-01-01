import {commitMutation, ConnectionHandler, graphql} from 'react-relay'
import type {Environment} from 'relay-runtime'
import type {
  AddBlockedByInput,
  addBlockedByMutation,
  addBlockedByMutation$data,
} from './__generated__/addBlockedByMutation.graphql'
import {BLOCKED_BY_LIST_ALL_RELAY_CONNECTION} from '../components/sections/relations-section/LazyRelationshipsBlockedByListView'
import {BLOCKING_LIST_ALL_RELAY_CONNECTION} from '../components/sections/relations-section/LazyRelationshipsBlockingListView'

export function addBlockedByMutation({
  environment,
  input,
  onError,
  onCompleted,
}: {
  environment: Environment
  input: AddBlockedByInput
  onError?: (error: Error) => void
  onCompleted?: (response: addBlockedByMutation$data) => void
}) {
  return commitMutation<addBlockedByMutation>(environment, {
    mutation: graphql`
      mutation addBlockedByMutation($input: AddBlockedByInput!) @raw_response_type {
        addBlockedBy(input: $input) {
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

import {commitMutation, graphql} from 'react-relay'
import type {Environment} from 'relay-runtime'

import type {
  IssueClosedStateReason,
  IssueState,
  UpdateIssuesBulkByQueryInput,
  updateIssuesBulkActionsByQueryMutation,
} from './__generated__/updateIssuesBulkActionsByQueryMutation.graphql'
import {updateIssuesById} from './update-issues-bulk-actions'

type issueUpdateArgs = {
  state: IssueState
  stateReason?: IssueClosedStateReason
}

export function commitUpdateIssueBulkByQueryMutation({
  environment,
  optimisticUpdateIds,
  input: {query, repositoryId, state, stateReason},
  onCompleted,
  onError,
}: {
  environment: Environment
  input: {query: string; repositoryId: string} & issueUpdateArgs
  optimisticUpdateIds: string[]
  onCompleted?: (response: updateIssuesBulkActionsByQueryMutation['response']) => void
  onError?: (error: Error) => void
}) {
  const inputArgs = {state, stateReason}
  const inputHash: UpdateIssuesBulkByQueryInput = {
    query,
    repositoryId,
    ...inputArgs,
  }

  return commitMutation<updateIssuesBulkActionsByQueryMutation>(environment, {
    mutation: graphql`
      mutation updateIssuesBulkActionsByQueryMutation($input: UpdateIssuesBulkByQueryInput!) @raw_response_type {
        updateIssuesBulkByQuery(input: $input) {
          jobId
        }
      }
    `,
    variables: {
      input: inputHash,
    },
    updater: store => updateIssuesById(store, optimisticUpdateIds, inputArgs),
    optimisticUpdater: store => updateIssuesById(store, optimisticUpdateIds, inputArgs),
    onCompleted: response => onCompleted && onCompleted(response),
    onError: error => onError && onError(error),
  })
}

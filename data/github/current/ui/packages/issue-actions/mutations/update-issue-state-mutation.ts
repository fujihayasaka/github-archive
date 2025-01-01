import {commitMutation, graphql} from 'react-relay'
import type {Environment} from 'relay-runtime'

import type {
  updateIssueStateMutation,
  updateIssueStateMutation$data,
} from './__generated__/updateIssueStateMutation.graphql'
import type {
  IssueClosedStateReason,
  updateIssueStateMutationCloseMutation,
  updateIssueStateMutationCloseMutation$data,
} from './__generated__/updateIssueStateMutationCloseMutation.graphql'

function changeIssuesTabCounter(delta: number) {
  const issuesTab = document.getElementById('issues-repo-tab-count')
  if (issuesTab === null) {
    return false
  }

  const newCount = Math.max(Number(issuesTab.title.replace(/\D/g, '')) + delta, 0)
  issuesTab.title = newCount.toLocaleString()

  const isRounded = !/^\d*$/.test(issuesTab.textContent || '')

  if (newCount === 0) {
    issuesTab.textContent = ''
  } else if (!isRounded && newCount <= 999) {
    issuesTab.textContent = newCount.toString()
  }

  return true
}

export function commitCloseIssueMutation({
  environment,
  input: {issueId, newStateReason, duplicateIssue},
  onError,
  onCompleted,
}: {
  environment: Environment
  input: {
    issueId: string
    newStateReason: IssueClosedStateReason
    duplicateIssue?: {id: string; number: number; url: string}
  }
  onError?: (error: Error) => void
  onCompleted?: (response: updateIssueStateMutationCloseMutation$data) => void
}) {
  return commitMutation<updateIssueStateMutationCloseMutation>(environment, {
    mutation: graphql`
      mutation updateIssueStateMutationCloseMutation(
        $id: ID!
        $newStateReason: IssueClosedStateReason!
        $duplicateIssueId: ID
      ) @raw_response_type {
        closeIssue(input: {issueId: $id, stateReason: $newStateReason, duplicateIssueId: $duplicateIssueId}) {
          issue {
            id
            state
            stateReason(enableDuplicate: true)
            duplicateOf {
              number
              url
            }
          }
        }
      }
    `,
    variables: {id: issueId, newStateReason, duplicateIssueId: duplicateIssue?.id},
    optimisticResponse: {
      closeIssue: {
        issue: {
          id: issueId,
          state: 'CLOSED',
          stateReason: newStateReason,
          duplicateOf: duplicateIssue
            ? {
                id: duplicateIssue.id,
                number: duplicateIssue.number,
                url: duplicateIssue.url,
              }
            : null,
        },
      },
    },
    onError: error => onError && onError(error),
    onCompleted: response => {
      if (onCompleted) {
        onCompleted(response)
      }
      changeIssuesTabCounter(-1)
    },
  })
}

export function commitReopenIssueMutation({
  environment,
  input: {issueId},
  onError,
  onCompleted,
}: {
  environment: Environment
  input: {issueId: string}
  onError?: (error: Error) => void
  onCompleted?: (response: updateIssueStateMutation$data) => void
}) {
  return commitMutation<updateIssueStateMutation>(environment, {
    mutation: graphql`
      mutation updateIssueStateMutation($id: ID!) @raw_response_type {
        reopenIssue(input: {issueId: $id}) {
          issue {
            id
            state
            duplicateOf {
              number
              url
            }
          }
        }
      }
    `,
    variables: {id: issueId},
    optimisticResponse: {
      reopenIssue: {
        issue: {
          id: issueId,
          state: 'OPEN',
          duplicateOf: null,
        },
      },
    },
    onError: error => onError && onError(error),
    onCompleted: response => {
      if (onCompleted) {
        onCompleted(response)
      }
      changeIssuesTabCounter(1)
    },
  })
}

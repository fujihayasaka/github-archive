import {commitMutation, graphql} from 'react-relay'
import type {Environment} from 'relay-runtime'

import type {Assignee} from '../components/AssigneePicker'
import type {
  replaceAssigneesForAssignableMutation,
  replaceAssigneesForAssignableMutation$data,
} from './__generated__/replaceAssigneesForAssignableMutation.graphql'

export function commitReplaceAssigneesForAssignableMutation({
  environment,
  input: {assignableId, assignees, participants, typename},
  onError,
  onCompleted,
}: {
  environment: Environment
  input: {assignableId: string; assignees: Assignee[]; participants: Assignee[]; typename: string}
  onError?: (error: Error) => void
  onCompleted?: (response: replaceAssigneesForAssignableMutation$data) => void
}) {
  // merge assignees and participants into one, unique by login
  const newParticipants = [...new Map([...assignees, ...participants].map(item => [item.login, item])).values()]

  return commitMutation<replaceAssigneesForAssignableMutation>(environment, {
    mutation: graphql`
      mutation replaceAssigneesForAssignableMutation($input: ReplaceAssigneesForAssignableInput!) @raw_response_type {
        replaceAssigneesForAssignable(input: $input) {
          assignable {
            assignees(first: 20) {
              nodes {
                ...AssigneePickerAssignee
              }
            }
            suggestedAssignees(first: 20) {
              nodes {
                ...AssigneePickerAssignee
              }
            }
          }
        }
      }
    `,
    variables: {input: {assignableId, assigneeIds: assignees.map(a => a.id)}},
    optimisticResponse: {
      replaceAssigneesForAssignable: {
        assignable: {
          id: assignableId,
          __isNode: 'true',
          __typename: typename,
          assignees: {
            nodes: assignees.map(a => {
              if (a.__typename === 'Bot') {
                return {
                  __typename: 'Bot',
                  __isActor: 'Bot',
                  __isNode: 'Bot',
                  id: a.id,
                  login: a.login,
                  name: a.name ?? null,
                  avatarUrl: a.avatarUrl,
                  profileResourcePath: a.profileResourcePath,
                  isCopilot: a.isCopilot || false,
                }
              } else {
                return {
                  __typename: 'User',
                  __isActor: 'User',
                  __isNode: 'User',
                  id: a.id,
                  login: a.login,
                  name: a.name ?? null,
                  avatarUrl: a.avatarUrl,
                  profileResourcePath: a.profileResourcePath,
                }
              }
            }),
          },
          suggestedAssignees: {
            nodes: newParticipants.map(a => {
              if (a.__typename === 'Bot') {
                return {
                  __typename: 'Bot',
                  __isActor: 'Bot',
                  __isNode: 'Bot',
                  id: a.id,
                  login: a.login,
                  name: a.name ?? null,
                  avatarUrl: a.avatarUrl,
                  profileResourcePath: a.profileResourcePath,
                  isCopilot: a.isCopilot || false,
                }
              } else {
                return {
                  __typename: 'User',
                  __isActor: 'User',
                  __isNode: 'User',
                  id: a.id,
                  login: a.login,
                  name: a.name ?? null,
                  avatarUrl: a.avatarUrl,
                  profileResourcePath: a.profileResourcePath,
                }
              }
            }),
          },
        },
      },
    },
    onError: error => onError && onError(error),
    onCompleted: response => onCompleted && onCompleted(response),
  })
}

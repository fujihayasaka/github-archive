import {commitMutation, graphql} from 'react-relay'
import type {Environment} from 'relay-runtime'

import type {Assignee} from '../components/AssigneePicker'
import type {
  replaceActorsForAssignableMutation,
  replaceActorsForAssignableMutation$data,
} from './__generated__/replaceActorsForAssignableMutation.graphql'

export function commitUpdateIssueAssigneesMutation({
  environment,
  input: {issueId, assignedActors, participants},
  onError,
  onCompleted,
}: {
  environment: Environment
  input: {issueId: string; assignedActors: Assignee[]; participants: Assignee[]}
  onError?: (error: Error) => void
  onCompleted?: (response: replaceActorsForAssignableMutation$data) => void
}) {
  // merge assigned actors and participants into one, unique by login and take the first 5
  // do not include copilot because today copilot does not show up as a participant on issues
  const newParticipants = [
    ...new Map([...assignedActors, ...participants].filter(a => !a.isCopilot).map(item => [item.login, item])).values(),
  ].slice(0, 5)

  // we use the `replaceActorsForAssignable` mutation specifically instead of `editIssue` as this has more specific permission
  // check for assignments.
  return commitMutation<replaceActorsForAssignableMutation>(environment, {
    mutation: graphql`
      mutation replaceActorsForAssignableMutation($input: ReplaceActorsForAssignableInput!) @raw_response_type {
        replaceActorsForAssignable(input: $input) {
          assignable {
            ... on Issue {
              id
              assignedActors(first: 20) {
                nodes {
                  ...AssigneePickerAssignee @dangerously_unaliased_fixme
                }
              }
              participants(first: 10) {
                nodes {
                  ...AssigneePickerAssignee
                }
              }
            }
          }
        }
      }
    `,
    variables: {input: {assignableId: issueId, actorIds: assignedActors.map(a => a.id)}},
    optimisticResponse: {
      replaceActorsForAssignable: {
        assignable: {
          __typename: 'Issue',
          __isNode: 'Issue',
          id: issueId,
          assignedActors: {
            nodes: assignedActors.map(a => {
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
          participants: {
            nodes: newParticipants.map(a => {
              if (a.__typename === 'Bot') {
                return {
                  __typename: 'Bot',
                  __isActor: 'Bot',
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

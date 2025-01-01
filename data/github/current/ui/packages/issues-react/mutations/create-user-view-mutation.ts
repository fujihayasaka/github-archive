import {commitMutation, graphql} from 'react-relay'
import type {Environment} from 'relay-runtime'

import type {
  CreateDashboardSearchShortcutInput,
  createUserViewMutation,
  createUserViewMutation$data,
} from './__generated__/createUserViewMutation.graphql'

type ViewMutationProps = {
  environment: Environment
  input: CreateDashboardSearchShortcutInput
  onError?: (error: Error) => void
  onCompleted?: (response: createUserViewMutation$data) => void
}

export function commitCreateUserViewMutation({environment, input, onError, onCompleted}: ViewMutationProps) {
  return commitMutation<createUserViewMutation>(environment, {
    mutation: graphql`
      mutation createUserViewMutation($input: CreateDashboardSearchShortcutInput!) @raw_response_type {
        createDashboardSearchShortcut(input: $input) {
          dashboard {
            ...SavedViewsShortcutsFragment
          }
          shortcut {
            id
            ...ListCurrentViewFragment
            ...IssueDetailCurrentViewFragment
            ...ViewOptionsButtonCurrentViewFragment
          }
        }
      }
    `,
    variables: {
      input,
    },
    onError: error => onError && onError(error),
    onCompleted: (response: createUserViewMutation$data) => {
      onCompleted?.(response)
    },
  })
}

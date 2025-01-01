import {type Environment, commitMutation, graphql} from 'react-relay'
import type {
  CreateLinkedBranchInput,
  createLinkedBranchMutation,
  createLinkedBranchMutation$data,
} from './__generated__/createLinkedBranchMutation.graphql'
import {ERRORS} from '@github-ui/item-picker/Errors'

export function commitCreateLinkedBranchMutation({
  environment,
  input,
  onError,
  onCompleted,
}: {
  environment: Environment
  input: CreateLinkedBranchInput
  onError?: (error: Error) => void
  onCompleted?: (response: createLinkedBranchMutation$data) => void
}) {
  return commitMutation<createLinkedBranchMutation>(environment, {
    mutation: graphql`
      mutation createLinkedBranchMutation($input: CreateLinkedBranchInput!) @raw_response_type {
        createLinkedBranch(input: $input) {
          linkedBranch {
            ref {
              id
              name
              prefix
            }
          }
          issue {
            ... on Issue {
              linkedBranches(first: 25) {
                nodes {
                  id
                  ref {
                    ...BranchPickerRef
                  }
                }
              }
              repository {
                refs(refPrefix: "refs/heads/", first: 25) {
                  nodes {
                    ...BranchPickerRef
                  }
                }
              }
            }
          }
          clientMutationId
          errors {
            message
          }
        }
      }
    `,
    variables: {input},
    onError: error => onError?.(error),
    onCompleted: response => {
      if (!response.createLinkedBranch?.linkedBranch) {
        if (response.createLinkedBranch?.errors) {
          response.createLinkedBranch.errors.map(e => {
            const message = ERRORS.branchAlreadyExists(input?.name ?? '')
            if (e.message === message) {
              onError?.({name: 'LinkedBranchExists', message})
            }
          })
        } else {
          onError?.({name: 'LinkedBranchNotFound', message: 'Linked branch not found'})
        }
      } else {
        onCompleted?.(response)
      }
    },
  })
}

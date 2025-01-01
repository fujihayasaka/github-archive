import {commitMutation, graphql} from 'react-relay'
import type {Environment} from 'relay-runtime'

import type {
  CreateIssueInput,
  createIssueMutation,
  createIssueMutation$data,
} from './__generated__/createIssueMutation.graphql'
import type {CreatedIssue} from '../utils/model'

type IssueMutationProps = {
  environment: Environment
  input: CreateIssueInput
  onError?: (error: Error) => void
  onCompleted?: (response: createIssueMutation$data) => void
}

type IssueMutationWithPromiseProps = {
  environment: Environment
  issueMetadata: IssueMetadata
  onError?: (error: Error) => void
  onCompleted?: (response: createIssueMutation$data) => void
}

export type IssueMetadata = {
  assigneeIds?: string[] | null | undefined
  body?: string | null | undefined
  issueTemplate?: string | null | undefined
  issueTypeId?: string | null | undefined
  labelIds?: string[] | null | undefined
  milestoneId?: string | null | undefined
  parentIssueId?: string | null | undefined
  projectIds?: string[] | null | undefined
  repositoryId: string
  title: string
}

export type IssueMutationResponse = {
  issue: CreatedIssue
  errors?: Array<{
    message: string
  }>
}

function extractMutationResponse(response: createIssueMutation$data): IssueMutationResponse {
  const {createIssue} = response
  if (!createIssue) {
    return {
      issue: {} as CreatedIssue,
      errors: [
        {
          message: 'An unknown error occurred while creating the issue.',
        },
      ],
    }
  }

  const {issue} = createIssue
  if (!issue) {
    return {
      issue: {} as CreatedIssue,
      errors: [
        {
          message: 'An unknown error occurred while creating the issue.',
        },
      ],
    }
  }

  return {
    issue,
    errors: createIssue.errors?.map(error => ({message: error.message})),
  }
}

export function commitCreateIssueMutation({
  environment,
  input: {title, body, repositoryId, labelIds, milestoneId, assigneeIds, issueTemplate, issueTypeId, parentIssueId},
  onError,
  onCompleted,
}: IssueMutationProps) {
  const inputHash: CreateIssueInput = {
    title,
    body,
    repositoryId,
    labelIds,
    milestoneId,
    assigneeIds,
    issueTemplate,
    issueTypeId,
    parentIssueId,
  }

  return commitMutation<createIssueMutation>(environment, {
    mutation: graphql`
      mutation createIssueMutation($input: CreateIssueInput!, $fetchParent: Boolean = false) @raw_response_type {
        createIssue(input: $input) {
          issue {
            databaseId
            repository {
              databaseId
              id
              name
              owner {
                login
              }
            }
            number
            title
            id
            number
            url
            # If this issue was a sub-issue of another issue, then we also fetch the parent's information so
            # that the UI will automatically update with the new sub-issues count.
            parent @include(if: $fetchParent) {
              id
              subIssues(first: 100) {
                totalCount
              }
              ...SubIssuesListView
            }
          }
          errors {
            message
          }
        }
      }
    `,
    variables: {
      input: inputHash,
      fetchParent: !!inputHash.parentIssueId,
    },
    onError: error => onError && onError(error),
    onCompleted: response => onCompleted && onCompleted(response),
  })
}

export function commitCreateIssueMutationWithPromise({environment, issueMetadata}: IssueMutationWithPromiseProps) {
  // Convert metadata mapping to input hash
  const input: CreateIssueInput = {
    repositoryId: issueMetadata.repositoryId,
    title: issueMetadata.title,
    body: issueMetadata.body,
    labelIds: issueMetadata.labelIds,
    assigneeIds: issueMetadata.assigneeIds,
    milestoneId: issueMetadata.milestoneId,
    issueTypeId: issueMetadata.issueTypeId,
    parentIssueId: issueMetadata.parentIssueId,
  }

  return new Promise<IssueMutationResponse>((resolve, reject) => {
    commitCreateIssueMutation({
      environment,
      input,
      onError: reject,
      onCompleted: response => resolve(extractMutationResponse(response)),
    })
  })
}

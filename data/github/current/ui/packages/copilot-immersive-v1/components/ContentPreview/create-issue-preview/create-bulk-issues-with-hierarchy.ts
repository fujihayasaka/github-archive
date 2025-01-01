import type {CreatedIssue} from '@github-ui/issue-create/Model'
import {
  commitCreateIssueMutationWithPromise,
  type IssueMetadata,
} from '@github-ui/issue-create/mutations/create-issue-mutation'
import type {ProjectPickerProject$data as Project} from '@github-ui/item-picker/ProjectPickerProject.graphql'
import {commitUpdateIssueProjectsMutation} from '@github-ui/item-picker/updateIssueProjectsMutation'
import type {Environment} from 'relay-runtime'

import type {DraftIssue} from '../content-preview-types'
import type {TreeNode} from './use-draft-issue-tree-map'

export type CreatedIssuesMetadata = {
  parentIssue: CreatedIssue
  createdIssues: CreatedIssue[]
}

export async function createBulkIssuesWithHierarchy(
  node: TreeNode<DraftIssue>,
  environment: Environment,
  issueMetadata: IssueMetadata,
  issueTemplate: string | null = null,
  isRoot: boolean = false,
  createdIssues: CreatedIssue[] = [],
  projects: Project[] = [],
  isBulkCreate: boolean = true,
): Promise<void | CreatedIssuesMetadata | Error> {
  try {
    const response = await commitCreateIssueMutationWithPromise({issueMetadata, environment})
    if (response.errors && response.errors.length > 0) {
      throw new Error(response.errors.map(error => error.message).join(', '))
    }

    const newIssue = response.issue
    const parentIssueId = newIssue.id
    createdIssues.push(newIssue)

    if (projects.length > 0) {
      assignIssueToProjects(newIssue.id, projects, environment)
    }

    if (node.children !== undefined && node.children.length > 0 && isBulkCreate) {
      await Promise.all(
        node.children.map(child => {
          const childMetadata: IssueMetadata = {
            repositoryId: issueMetadata.repositoryId,
            title: child.item.name,
            body: child.item.body,
            labelIds: issueMetadata.labelIds,
            assigneeIds: issueMetadata.assigneeIds,
            milestoneId: issueMetadata.milestoneId,
            issueTypeId: issueMetadata.issueTypeId,
            issueTemplate,
            parentIssueId,
          }

          return createBulkIssuesWithHierarchy(
            child,
            environment,
            childMetadata,
            issueTemplate,
            false,
            createdIssues,
            projects,
          )
        }),
      )
    }

    if (isRoot) {
      return {
        parentIssue: newIssue,
        createdIssues,
      }
    }
  } catch (error) {
    const errorResponse = error as Error
    return errorResponse
  }
}

function assignIssueToProjects(issueId: string, projects: Project[], environment: Environment) {
  for (const project of projects) {
    commitUpdateIssueProjectsMutation({environment, issueId, projectId: project.id})
  }
}

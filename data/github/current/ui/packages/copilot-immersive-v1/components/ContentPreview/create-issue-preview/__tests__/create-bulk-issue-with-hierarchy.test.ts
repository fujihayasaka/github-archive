import type {CreatedIssue} from '@github-ui/issue-create/Model'
import {
  commitCreateIssueMutationWithPromise,
  type IssueMetadata,
} from '@github-ui/issue-create/mutations/create-issue-mutation'
import type {Environment, FragmentRefs} from 'relay-runtime'

import type {DraftIssue} from '../../content-preview-types'
import {createBulkIssuesWithHierarchy} from '../create-bulk-issues-with-hierarchy'
import type {TreeNode} from '../use-draft-issue-tree-map'
import type {Project} from '../use-projects-query'

const mockCommitUpdateIssueProjectsMutation = jest.fn()
const mockRelayEnvironment = jest.fn()

jest.mock('@github-ui/issue-create/mutations/create-issue-mutation')
function mockCommitCreateIssueMutationWithPromise(): void {
  jest
    .mocked(commitCreateIssueMutationWithPromise)
    .mockImplementationOnce(() => {
      return Promise.resolve({
        issue: {
          databaseId: null,
          repository: {databaseId: 123, id: 'repo-id', name: 'repo-name', owner: {login: 'owner-login'}},
          id: 'new-issue:root#1',
          number: 1,
          title: 'Issue Title',
          url: 'http://example.com',
        } as CreatedIssue,
        errors: [],
      })
    })
    .mockImplementationOnce(() => {
      return Promise.resolve({
        issue: {
          id: 'new-issue:child#1',
          databaseId: null,
          number: 2,
          repository: {databaseId: 123, id: 'repo-id', name: 'repo-name', owner: {login: 'owner-login'}},
          title: 'Child Issue Title',
          url: 'http://example.com',
          body: 'Child Issue Body',
          parent: {
            id: 'new-issue:root#1',
            subIssues: {totalCount: 1},
            ' $fragmentSpreads': {} as FragmentRefs<'SubIssuesListView'>,
          },
        } as CreatedIssue,
        errors: [],
      })
    })
    .mockImplementationOnce(() => {
      return Promise.resolve({
        issue: {
          id: 'new-issue:grandchild#1',
          databaseId: null,
          number: 3,
          repository: {databaseId: 123, id: 'repo-id', name: 'repo-name', owner: {login: 'owner-login'}},
          title: 'Grandchild Issue Title',
          url: 'http://example.com',
          body: 'Grandchild Issue Body',
          parent: {
            id: 'new-issue:child#1',
            subIssues: {totalCount: 1},
            ' $fragmentSpreads': {} as FragmentRefs<'SubIssuesListView'>,
          },
        } as CreatedIssue,
        errors: [],
      })
    })
}

function mockCommitCreateIssueMutationWithPromiseWithErrors(): void {
  jest.mocked(commitCreateIssueMutationWithPromise).mockImplementationOnce(() => {
    return Promise.resolve({
      issue: {} as CreatedIssue,
      errors: [{message: 'Failed to create issue'}],
    })
  })
}

jest.mock('@github-ui/item-picker/updateIssueProjectsMutation', () => ({
  commitUpdateIssueProjectsMutation: jest.fn(() => mockCommitUpdateIssueProjectsMutation()),
}))

jest.mock('react-relay', () => ({
  useRelayEnvironment: jest.fn(() => {
    return mockRelayEnvironment()
  }),
}))

function createIssueHierarchy() {
  const baseProps: DraftIssue = {
    repository: 'repoA',
    type: 'new-issue',
    name: 'Issue Title',
    body: 'Issue Body',
    assignees: [],
    labels: [],
    projects: [],
    isUserEdited: false,
    tag: 'root',
    id: 'new-issue:root#1',
    messageId: 'message-id-1',
  }
  const parentIssue: DraftIssue = {
    ...baseProps,
    tag: 'root',
    id: 'new-issue:root#1',
    messageId: 'message-id-1',
  }
  const childIssue: DraftIssue = {
    ...baseProps,
    tag: 'child',
    id: 'new-issue:child#1',
    messageId: 'message-id-2',
    parentTag: 'root',
  }
  const grandChildIssue: DraftIssue = {
    ...baseProps,
    tag: 'grandchild',
    id: 'new-issue:grandchild#1',
    messageId: 'message-id-2',
    parentTag: 'child',
  }
  const draftIssues: DraftIssue[] = [parentIssue, childIssue, grandChildIssue]
  const draftIssuesMap = draftIssues.reduce((acc, issue) => {
    acc.set(issue.tag, {item: issue, parent: null, children: []})
    return acc
  }, new Map<string, TreeNode<DraftIssue>>())

  for (const draftIssue of draftIssues) {
    if (!draftIssue.parentTag) continue
    const parentNode = draftIssuesMap.get(draftIssue.parentTag)
    const currentNode = draftIssuesMap.get(draftIssue.tag)
    if (parentNode && currentNode) {
      currentNode.parent = parentNode

      parentNode.children.push(currentNode)
    }
  }

  // Return the mapping
  return draftIssuesMap
}

function createIssueInput(issue: DraftIssue, parentIssueId?: string): IssueMetadata {
  const issueMetadata: IssueMetadata = {
    repositoryId: '123',
    title: issue.name,
    body: issue.body,
    labelIds: [],
    assigneeIds: [],
    milestoneId: null,
    issueTypeId: null,
    issueTemplate: null,
    parentIssueId: parentIssueId || undefined,
  }
  return issueMetadata
}

const issueNode = createIssueHierarchy().get('root') as TreeNode<DraftIssue>
const environment: Environment = mockRelayEnvironment()
const hashInput = createIssueInput(issueNode.item)
const issueTemplate = null
const isRoot = true
const createdIssues: CreatedIssue[] = []
const projects: Project[] = []
const isBulkCreate = true

describe('createBulkIssuesWithHierarchy', () => {
  beforeEach(() => {
    jest.resetAllMocks()
  })

  it('should recursively create all issues within the tree', async () => {
    mockCommitCreateIssueMutationWithPromise()

    const response = await createBulkIssuesWithHierarchy(
      issueNode,
      environment,
      hashInput,
      issueTemplate,
      isRoot,
      createdIssues,
      projects,
      isBulkCreate,
    )

    expect(commitCreateIssueMutationWithPromise).toHaveBeenCalledTimes(3)
    expect(response).toEqual({
      parentIssue: expect.objectContaining({
        id: 'new-issue:root#1',
        title: 'Issue Title',
      }),
      createdIssues: expect.arrayContaining([
        expect.objectContaining({id: 'new-issue:root#1'}),
        expect.objectContaining({id: 'new-issue:child#1'}),
        expect.objectContaining({id: 'new-issue:grandchild#1'}),
      ]),
    })
  })

  it('should only create one issue if it does not have any children', async () => {
    mockCommitCreateIssueMutationWithPromise()

    const issueNodeWithoutChildren = {...issueNode}
    issueNodeWithoutChildren.children = []

    const response = await createBulkIssuesWithHierarchy(
      issueNodeWithoutChildren,
      environment,
      hashInput,
      issueTemplate,
      isRoot,
      createdIssues,
      projects,
      isBulkCreate,
    )

    expect(commitCreateIssueMutationWithPromise).toHaveBeenCalledTimes(1)
    expect(response).toEqual({
      parentIssue: expect.objectContaining({
        id: 'new-issue:root#1',
        title: 'Issue Title',
      }),
      createdIssues: expect.arrayContaining([expect.objectContaining({id: 'new-issue:root#1'})]),
    })
  })

  it('should only create one issue if it has children but bulk create option is not selected', async () => {
    mockCommitCreateIssueMutationWithPromise()

    const response = await createBulkIssuesWithHierarchy(
      issueNode,
      environment,
      hashInput,
      issueTemplate,
      isRoot,
      createdIssues,
      projects,
      false,
    )

    expect(commitCreateIssueMutationWithPromise).toHaveBeenCalledTimes(1)
    expect(response).toEqual({
      parentIssue: expect.objectContaining({
        id: 'new-issue:root#1',
        title: 'Issue Title',
      }),
      createdIssues: expect.arrayContaining([expect.objectContaining({id: 'new-issue:root#1'})]),
    })
  })

  it('should return an error if the creation fails', async () => {
    mockCommitCreateIssueMutationWithPromiseWithErrors()

    const response = await createBulkIssuesWithHierarchy(
      issueNode,
      environment,
      hashInput,
      issueTemplate,
      isRoot,
      createdIssues,
      projects,
      isBulkCreate,
    )

    expect(commitCreateIssueMutationWithPromise).toHaveBeenCalledTimes(1)
    expect(response).toBeInstanceOf(Error)
    expect((response as Error).message).toBe('Failed to create issue')
  })
})

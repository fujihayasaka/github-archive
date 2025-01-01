import type {TextReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {renderHook} from '@github-ui/react-core/test-utils'
import {act} from 'react'

import type {OnCreateBulkProps} from '../use-on-create-bulk-callback'
import {useOnCreateBulkCallback} from '../use-on-create-bulk-callback'

const updateItem = jest.fn()
const openItem = jest.fn()
const openPreviewPane = jest.fn()
const closeItem = jest.fn()
const mockContentPreview = {
  items: new Map(),
  updateItem,
  openItem,
  closeItem,
  openPreviewPane,
}
jest.mock('../../ContentPreviewContext', () => ({
  useContentPreview: jest.fn(() => mockContentPreview),
}))

// Mock useChatState
const mockChatState = {
  currentUserLogin: 'test-user',
  currentTopic: 'test-topic',
  context: 'test-context',
  customInstructions: 'test-instructions',
  model: 'test-model',
}
jest.mock('@github-ui/copilot-chat/CopilotChatContext', () => ({
  useChatState: jest.fn(() => mockChatState),
}))

const mockChatManager = {
  getSelectedThread: jest.fn(() => ({id: 'thread-id'})),
  sendChatMessage: jest.fn(),
}
jest.mock('@github-ui/copilot-chat/CopilotChatManagerContext', () => ({
  useChatManager: jest.fn(() => mockChatManager),
}))

const EDITED_NEW_ISSUE_ID = 'new-issue:tag1#123'
jest.mock('../use-user-edited-new-issue-id', () => ({
  useUserEditedNewIssueId: () => EDITED_NEW_ISSUE_ID,
}))

function parentIssue(overrides?: Partial<OnCreateBulkProps['parentIssue']>): OnCreateBulkProps['parentIssue'] {
  return {
    databaseId: 123,
    number: 123,
    id: 'issue:orgA/repoA/123',
    repository: {
      databaseId: 123,
      id: '321',
      name: 'repoA',
      owner: {
        login: 'orgA',
      },
    },
    title: 'Issue Title',
    url: 'repoA/issues/123',
    ...overrides,
  }
}

function subIssues(overrides?: Partial<OnCreateBulkProps['createdIssues']>): OnCreateBulkProps['createdIssues'] {
  return [
    {
      databaseId: 123,
      number: 123,
      id: 'issue:orgA/repoA/123',
      repository: {
        databaseId: 123,
        id: '321',
        name: 'repoA',
        owner: {
          login: 'orgA',
        },
      },
      title: 'Issue Title',
      url: 'repoA/issues/123',
      ...overrides,
    },
    {
      databaseId: 456,
      number: 456,
      id: 'issue:orgA/repoA/456',
      repository: {
        databaseId: 456,
        id: '654',
        name: 'repoA',
        owner: {
          login: 'orgA',
        },
      },
      title: 'Another Issue Title',
      url: 'repoB/issues/456',
      ...overrides,
    },
    {
      databaseId: 789,
      number: 789,
      id: 'issue:orgA/repoA/789',
      repository: {
        databaseId: 789,
        id: '987',
        name: 'repoA',
        owner: {
          login: 'orgA',
        },
      },
      title: 'Yet Another Issue Title',
      url: 'repoC/issues/789',
      ...overrides,
    },
  ]
}

function instructions(issuesData: OnCreateBulkProps['createdIssues']): TextReference {
  const issuesInstructions = ''
  for (const issueData of issuesData) {
    const number = issueData.number
    const owner = issueData.repository.owner.login
    const title = issueData.title

    issuesInstructions.concat(
      `- url: ${issueData.url}\n` +
        '  state: "open"\n' +
        '  draft: false\n' +
        `  title: "${title}"\n` +
        `  number: ${number}\n` +
        `  author: ${owner}\n` +
        '  created_at: "2025-03-27T12:00:00Z"\n' +
        '  closed_at: "2025-03-27T12:00:00Z"\n' +
        '  labels:\n' +
        '  - name: "bug"\n' +
        '  - name: "good first issue"\n',
    )
  }
  return {
    type: 'text',
    name: `timeline-event: {"type": "issue-created", "markdownContent": "Creating issues..."}`,
    text:
      `Fetch the details for all saved issues and return them in a code block with YAML following this example format:\n` +
      `\`\`\`list type="issue"\n` +
      `data:\n${issuesInstructions}\`\`\``,
  }
}

describe('useOnCreateCallback', () => {
  it('should create all issues and open preview pane for parent issue', async () => {
    const tag = 'tag1'
    const createdRootIssue = parentIssue()
    const createdIssues = subIssues()
    const {result} = renderHook(() => useOnCreateBulkCallback({tag}))
    const instructionsData = instructions(createdIssues)

    await act(() => result.current({parentIssue: createdRootIssue, createdIssues}))

    expect(updateItem).toHaveBeenCalledTimes(3)
    expect(closeItem).toHaveBeenCalledWith(EDITED_NEW_ISSUE_ID)
    expect(openItem).toHaveBeenCalledWith(createdRootIssue.id)
    expect(openPreviewPane).toHaveBeenCalled()
    expect(mockChatManager.sendChatMessage).toHaveBeenCalledWith(
      expect.objectContaining({
        references: [instructionsData],
      }),
    )
  })
})

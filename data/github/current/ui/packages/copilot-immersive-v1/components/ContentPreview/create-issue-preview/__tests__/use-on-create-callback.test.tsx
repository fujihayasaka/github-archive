// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {
  type DraftIssueReference,
  NullMessageId,
  type TextReference,
} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import type {OnCreateProps} from '@github-ui/issue-create/Model'
import {renderHook} from '@github-ui/react-core/test-utils'
import {act} from 'react'

import type {DraftIssue, PreviewableContent} from '../../content-preview-types'
import {useContentPreview} from '../../ContentPreviewContext'
import {useOnChangeCallback} from '../use-on-change-callback'
import {useOnCreateCallback} from '../use-on-create-callback'

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

function newIssue(overrides?: Partial<OnCreateProps['issue']>): OnCreateProps['issue'] {
  return {
    databaseId: 123,
    number: 123,
    id: 'issue:tag1#123',
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

function createIssueFromData(issueData: OnCreateProps['issue']): PreviewableContent {
  return {
    id: `issue:${issueData.repository.owner.login}/${issueData.repository.name}/${issueData.number}`,
    messageId: NullMessageId,
    name: issueData.title,
    owner: issueData.repository.owner.login,
    repo: issueData.repository.name,
    number: issueData.number,
    href: issueData.url,
    type: 'issue',
  }
}

function editedIssue(issueData: OnCreateProps['issue']): DraftIssue {
  return {
    type: 'new-issue',
    tag: 'tag1',
    id: EDITED_NEW_ISSUE_ID,
    repository: `${issueData.repository.owner.login}/${issueData.repository.name}`,
    name: issueData.title,
    body: 'Issue Description',
    assignees: [],
    labels: [],
    issueType: 'bug',
    projects: [],
    milestone: undefined,
    messageId: '123',
    isUserEdited: false,
  }
}

function instructions(issueData: OnCreateProps['issue']): TextReference {
  return {
    type: 'text',
    name: `timeline-event: {"type": "issue-created", "markdownContent": "Issue saved to [${issueData.repository.owner.login}/${issueData.repository.name}#${issueData.number}](${issueData.url})"}`,
    text:
      'Fetch the issue details and return them in a code block with YAML following this example format:\n' +
      '```list type="issue"\n' +
      'data:\n' +
      `- url: ${issueData.url}\n` +
      '  state: "open"\n' +
      '  draft: false\n' +
      `  title: "${issueData.title}"\n` +
      `  number: ${issueData.number}\n` +
      `  author: test-user\n` +
      '  created_at: "2025-03-27T12:00:00Z"\n' +
      '  closed_at: "2025-03-27T12:00:00Z"\n' +
      '  labels:\n' +
      '  - name: "bug"\n' +
      '  - name: "good first issue"\n' +
      '```',
  }
}

describe('useOnCreateCallback', () => {
  it('should create issue and open preview pane', async () => {
    const tag = 'tag1'
    const createdIssue = newIssue()
    const previewableIssue = createIssueFromData(createdIssue)
    const {result} = renderHook(() => useOnCreateCallback({tag}))

    await act(() => result.current(createdIssue))

    expect(updateItem).toHaveBeenCalledWith(previewableIssue)
    expect(closeItem).toHaveBeenCalledWith(EDITED_NEW_ISSUE_ID)
    expect(openItem).toHaveBeenCalledWith(previewableIssue.id)
    expect(openPreviewPane).toHaveBeenCalled()
  })

  it('should create issue and not open preview pane if already open', async () => {
    const tag = 'tag1'
    const createdIssue = newIssue()
    const previewableIssue = createIssueFromData(createdIssue)
    const {result} = renderHook(() => useOnCreateCallback({tag}))

    await act(() => result.current(createdIssue))

    expect(updateItem).toHaveBeenCalledWith(previewableIssue)
    expect(closeItem).toHaveBeenCalledWith(EDITED_NEW_ISSUE_ID)
    expect(openItem).toHaveBeenCalledWith(previewableIssue.id)
    expect(openPreviewPane).toHaveBeenCalled()
  })

  it('should include a draft issue in references if issue is edited before creation', async () => {
    const tag = 'tag1'
    const createdIssue = newIssue()
    const draftIssue = editedIssue(createdIssue)
    const previewableIssue = createIssueFromData(createdIssue)
    const instructionsData = instructions(createdIssue)

    const {result: onChangeResult} = renderHook(() => useOnChangeCallback(draftIssue))
    act(() => {
      onChangeResult.current({name: 'new title who dis'})
    })
    ;(useContentPreview as jest.Mock).mockReturnValue({
      items: new Map([
        [EDITED_NEW_ISSUE_ID, {...draftIssue, name: 'new title who dis', id: EDITED_NEW_ISSUE_ID, isUserEdited: true}],
      ]),
      updateItem,
      openItem,
      closeItem,
      openPreviewPane,
    })
    const {result} = renderHook(() => useOnCreateCallback({tag}))
    await act(() => result.current(createdIssue))

    expect(updateItem).toHaveBeenCalledWith(previewableIssue)
    expect(openItem).toHaveBeenCalledWith(previewableIssue.id)
    expect(openPreviewPane).toHaveBeenCalled()
    expect(mockChatManager.sendChatMessage).toHaveBeenCalledWith(
      expect.objectContaining({
        references: [
          instructionsData,
          expect.objectContaining({
            type: 'draft-issue',
            title: 'new title who dis',
          }),
        ],
      }),
    )
  })

  it('should not include draft issues in references if issue is created with no edits', async () => {
    const tag = 'tag1'
    const createdIssue = newIssue()
    const previewableIssue = createIssueFromData(createdIssue)
    const instructionsData = instructions(createdIssue)

    const {result} = renderHook(() => useOnCreateCallback({tag}))
    await act(() => result.current(createdIssue))

    expect(updateItem).toHaveBeenCalledWith(previewableIssue)
    expect(openItem).toHaveBeenCalledWith(previewableIssue.id)
    expect(openPreviewPane).toHaveBeenCalled()
    expect(mockChatManager.sendChatMessage).toHaveBeenCalledWith(
      expect.objectContaining({
        references: [
          instructionsData,
          expect.not.objectContaining({type: 'draft-issue'} satisfies Pick<DraftIssueReference, 'type'>), // Satisfies here makes sure we use the right type when asserting an object does NOT have something to avoid the test passing just because the type used here is wrong
        ],
      }),
    )
  })
})

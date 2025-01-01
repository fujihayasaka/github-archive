import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {renderHook} from '@github-ui/react-core/test-utils'
import {useSessionStorage} from '@github-ui/use-safe-storage/session-storage'
import {act} from 'react'

import type {DraftIssue} from '../../content-preview-types'
import {useContentPreview} from '../../ContentPreviewContext'
import {useOnChangeCallback} from '../use-on-change-callback'

jest.mock('../../ContentPreviewContext', () => ({
  useContentPreview: jest.fn(),
}))

// Mock useChatState
const mockChatState = {
  selectedThreadID: 'thread-id',
}
jest.mock('@github-ui/copilot-chat/CopilotChatContext', () => ({
  useChatState: jest.fn(() => mockChatState),
}))

const EDITED_NEW_ISSUE_ID = 'new-issue:tag1#123'
jest.mock('../use-user-edited-new-issue-id', () => ({
  useUserEditedNewIssueId: () => EDITED_NEW_ISSUE_ID,
}))

jest.mock('@github-ui/use-safe-storage/session-storage', () => ({
  useSessionStorage: jest.fn(),
}))
const mockWriteEditedIssueToStorage = jest.fn()
;(useSessionStorage as jest.Mock).mockReturnValue([undefined, mockWriteEditedIssueToStorage])

function newIssue(overrides?: Partial<DraftIssue>): DraftIssue {
  return {
    type: 'new-issue',
    tag: 'tag1',
    id: 'new-issue:123#456',
    repository: 'orgA/repoA',
    name: 'Issue Title',
    body: 'Issue Description',
    assignees: [],
    labels: [],
    issueType: 'bug',
    projects: [],
    milestone: undefined,
    messageId: '123',
    isUserEdited: false,
    ...overrides,
  }
}

describe('useOnChangeCallback', () => {
  beforeEach(() => {
    jest.clearAllMocks()
    jest.spyOn(copilotFeatureFlags, 'copilotPersistEditedDraftIssues', 'get').mockReturnValue(true)
  })

  it('should not update if no changes', () => {
    const updateItem = jest.fn()
    const openItem = jest.fn()
    ;(useContentPreview as jest.Mock).mockReturnValue({
      updateItem,
      openItem,
    })

    const draftIssue = newIssue()
    const {result} = renderHook(() => useOnChangeCallback(draftIssue))

    act(() => {
      result.current({}) // No changes
    })

    expect(mockWriteEditedIssueToStorage).not.toHaveBeenCalled()
    expect(updateItem).not.toHaveBeenCalled()
    expect(openItem).not.toHaveBeenCalled()
  })

  it('should handle explicit undefined value', () => {
    const updateItem = jest.fn()
    const openItem = jest.fn()
    ;(useContentPreview as jest.Mock).mockReturnValue({
      updateItem,
      openItem,
    })

    const draftIssue = newIssue()
    const {result} = renderHook(() => useOnChangeCallback(draftIssue))

    act(() => {
      result.current({name: undefined})
    })

    expect(mockWriteEditedIssueToStorage).toHaveBeenCalledWith(
      expect.objectContaining({
        ...draftIssue,
        name: undefined,
        id: EDITED_NEW_ISSUE_ID,
        isUserEdited: true,
      }),
    )
    expect(updateItem).toHaveBeenCalledWith(
      expect.objectContaining({
        ...draftIssue,
        name: undefined,
        id: EDITED_NEW_ISSUE_ID,
        isUserEdited: true,
      }),
    )
    expect(openItem).toHaveBeenCalled()
  })

  it('should update if the title changes', () => {
    const updateItem = jest.fn()
    const openItem = jest.fn()
    ;(useContentPreview as jest.Mock).mockReturnValue({
      updateItem,
      openItem,
    })

    const draftIssue = newIssue()
    const {result} = renderHook(() => useOnChangeCallback(draftIssue))

    act(() => {
      result.current({name: 'new title who dis'})
    })

    expect(mockWriteEditedIssueToStorage).toHaveBeenCalledWith(
      expect.objectContaining({
        ...draftIssue,
        name: 'new title who dis',
        id: EDITED_NEW_ISSUE_ID,
        isUserEdited: true,
      }),
    )
    expect(updateItem).toHaveBeenCalledWith(
      expect.objectContaining({
        ...draftIssue,
        name: 'new title who dis',
        id: EDITED_NEW_ISSUE_ID,
        isUserEdited: true,
      }),
    )
    expect(openItem).toHaveBeenCalled()
  })

  it('should update if the description changes', () => {
    const updateItem = jest.fn()
    const openItem = jest.fn()
    ;(useContentPreview as jest.Mock).mockReturnValue({
      updateItem,
      openItem,
    })

    const draftIssue = newIssue()
    const {result} = renderHook(() => useOnChangeCallback(draftIssue))

    act(() => {
      result.current({body: 'updated description'})
    })

    expect(mockWriteEditedIssueToStorage).toHaveBeenCalledWith(
      expect.objectContaining({
        ...draftIssue,
        body: 'updated description',
        id: EDITED_NEW_ISSUE_ID,
        isUserEdited: true,
      }),
    )
    expect(updateItem).toHaveBeenCalledWith(
      expect.objectContaining({
        ...draftIssue,
        body: 'updated description',
        id: EDITED_NEW_ISSUE_ID,
        isUserEdited: true,
      }),
    )
    expect(openItem).toHaveBeenCalled()
  })

  it('should update if the assignees change', () => {
    const updateItem = jest.fn()
    const openItem = jest.fn()
    ;(useContentPreview as jest.Mock).mockReturnValue({
      updateItem,
      openItem,
    })

    const draftIssue = newIssue()
    const {result} = renderHook(() => useOnChangeCallback(draftIssue))

    act(() => {
      result.current({assignees: ['user1', 'user2']})
    })

    expect(mockWriteEditedIssueToStorage).toHaveBeenCalledWith(
      expect.objectContaining({
        ...draftIssue,
        assignees: ['user1', 'user2'],
        id: EDITED_NEW_ISSUE_ID,
        isUserEdited: true,
      }),
    )
    expect(updateItem).toHaveBeenCalledWith({
      ...draftIssue,
      assignees: ['user1', 'user2'],
      id: EDITED_NEW_ISSUE_ID,
      isUserEdited: true,
    })
  })

  it('should update owner and repo if the they change', () => {
    const updateItem = jest.fn()
    const openItem = jest.fn()
    ;(useContentPreview as jest.Mock).mockReturnValue({
      updateItem,
      openItem,
    })

    const draftIssue = newIssue()
    const {result} = renderHook(() => useOnChangeCallback(draftIssue))

    act(() => {
      result.current({repository: 'orgB/repoB'})
    })

    expect(mockWriteEditedIssueToStorage).toHaveBeenCalledWith(
      expect.objectContaining({
        ...draftIssue,
        repository: 'orgB/repoB',
        id: EDITED_NEW_ISSUE_ID,
        isUserEdited: true,
      }),
    )
    expect(updateItem).toHaveBeenCalledWith(
      expect.objectContaining({
        ...draftIssue,
        repository: 'orgB/repoB',
        id: EDITED_NEW_ISSUE_ID,
        isUserEdited: true,
      }),
    )
    expect(openItem).toHaveBeenCalled()
  })

  it('should update owner and repo while skipping version bump if requested', () => {
    const updateItem = jest.fn()
    const openItem = jest.fn()
    ;(useContentPreview as jest.Mock).mockReturnValue({
      updateItem,
      openItem,
    })

    const draftIssue = newIssue()
    const {result} = renderHook(() => useOnChangeCallback(draftIssue))

    act(() => {
      result.current({repository: 'orgB/repoB'}, true) // Skip version bump
    })

    expect(mockWriteEditedIssueToStorage).not.toHaveBeenCalled()
    expect(updateItem).toHaveBeenCalledWith(
      expect.objectContaining({
        ...draftIssue,
        repository: 'orgB/repoB',
      }),
    )
    expect(openItem).toHaveBeenCalled()
  })
})

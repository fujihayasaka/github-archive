// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {ChatStateProvider} from '@github-ui/copilot-chat/CopilotChatContext'
import {getDefaultReducerState, getMessageMock} from '@github-ui/copilot-chat/test-utils/mock-data'
import type {CopilotChatMessage} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {renderHook} from '@testing-library/react'

import type {DraftIssue} from '../../content-preview-types'
import {usePreProcessedNewIssue} from '../use-pre-processed-new-issue'

function getNewIssue(overrides?: Partial<DraftIssue>): DraftIssue {
  return {
    type: 'new-issue',
    tag: 'tag1',
    id: 'new-issue:123#456',
    repository: 'orgA/repoA',
    name: 'Issue Title',
    body: 'Issue Description',
    assignees: [],
    labels: [],
    issueType: 'task',
    projects: [],
    messageId: '123',
    isUserEdited: false,
    ...overrides,
  }
}

function renderHookWithProvider(newIssue: DraftIssue, messages: CopilotChatMessage[] = []) {
  return renderHook(() => usePreProcessedNewIssue(newIssue), {
    wrapper: ({children}) => {
      return (
        <ChatStateProvider state={{...getDefaultReducerState('2', undefined, 'immersive'), messages}}>
          {children}
        </ChatStateProvider>
      )
    },
  })
}

describe('usePreProcessedNewIssue', () => {
  describe('body', () => {
    describe('image placeholders', () => {
      it('replaces image placeholders with URLs and returns a new object', () => {
        const newIssue = getNewIssue({
          body: 'Issue Description\n![alt text 1](image1)\n![alt text 2](image2)',
        })

        const media = ['image1.png', 'image2.png'].map(name => ({
          mediaType: 'image',
          name,
          url: `https://example.com/${name}`,
        }))

        const messages = media.map((mediaItem, index) => ({
          ...getMessageMock(),
          id: index.toString(),
          mediaContent: [mediaItem],
          selectedChildIndex: index + 1,
        }))

        const {result} = renderHookWithProvider(newIssue, messages)

        expect(result.current.body).toEqual(
          'Issue Description\n![alt text 1](https://example.com/image2.png)\n![alt text 2](https://example.com/image1.png)',
        )
        expect(result.current).not.toBe(newIssue)
      })

      it('returns the original object when no image placeholders are present', () => {
        const newIssue = getNewIssue({
          body: 'Issue Description',
        })

        const media = ['image1.png'].map(name => ({
          mediaType: 'image',
          name,
          url: `https://example.com/${name}`,
        }))

        const messages = media.map((mediaItem, index) => ({
          ...getMessageMock(),
          id: index.toString(),
          mediaContent: [mediaItem],
          selectedChildIndex: index + 1,
        }))

        const {result} = renderHookWithProvider(newIssue, messages)

        expect(result.current.body).toEqual('Issue Description')
        expect(result.current).toBe(newIssue)
      })
    })
  })
})

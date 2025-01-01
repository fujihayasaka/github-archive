import {CopilotChatProvider} from '@github-ui/copilot-chat/CopilotChatContext'
import {getCopilotChatProviderProps} from '@github-ui/copilot-chat/test-utils/mock-data'
import type {DraftIssueReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {ContentPreviewProvider} from '../ContentPreview/ContentPreviewContext'
import {TimelineEvents} from '../TimelineEvents'

describe('UserMessageTimelineEvent', () => {
  it('Renders an switch-issue-template event', async () => {
    render(
      <CopilotChatProvider {...getCopilotChatProviderProps()} topic={undefined} threadId="3" mode="immersive">
        <ContentPreviewProvider>
          <TimelineEvents
            message={{
              id: '12',
              role: 'assistant',
              createdAt: '2020-01-01T00:00:00Z',
              threadID: '12',
              references: [
                {
                  type: 'text',
                  name: 'timeline-event: {"type": "switch-issue-template", "markdownContent": "Removing template…"}',
                },
              ],
              content: "Template changed to 'Bug Report'",
            }}
            messageIndex={2}
            isViewingSharedThread={false}
          />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    expect(await screen.findByText('Removing template…')).toBeInTheDocument()
  })

  it('Renders a issue-created', async () => {
    render(
      <CopilotChatProvider {...getCopilotChatProviderProps()} topic={undefined} threadId="3" mode="immersive">
        <ContentPreviewProvider>
          <TimelineEvents
            message={{
              id: '12',
              role: 'assistant',
              createdAt: '2020-01-01T00:00:00Z',
              threadID: '12',
              references: [
                {
                  type: 'text',
                  name: 'timeline-event: {"type": "issue-created", "markdownContent": "Issue saved to [test-org/private-repo#1](github.com/test-org/private-repo/issues#1)"}',
                },
              ],
              content: 'Issue saved to [test-org/private-repo#1](github.com/test-org/private-repo/issues#1)',
            }}
            messageIndex={2}
            isViewingSharedThread={false}
          />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    expect(await screen.findByText('Issue saved to')).toBeInTheDocument()
    const issueUrl = screen.getByText('test-org/private-repo#1')
    expect(issueUrl).toBeInTheDocument()
    expect(issueUrl.getAttribute('href')).toBe('github.com/test-org/private-repo/issues#1')
  })

  it('Does not renders a non-timeline event', () => {
    render(
      <CopilotChatProvider {...getCopilotChatProviderProps()} topic={undefined} threadId="3" mode="immersive">
        <ContentPreviewProvider>
          <TimelineEvents
            message={{
              id: '12',
              role: 'assistant',
              createdAt: '2020-01-01T00:00:00Z',
              threadID: '12',
              references: [
                {
                  type: 'text',
                  name: 'fake-reference',
                },
              ],
              content: 'Message with reference',
            }}
            messageIndex={2}
            isViewingSharedThread={false}
          />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    expect(screen.queryByText('Message with reference')).not.toBeInTheDocument()
  })

  it('Renders version references', async () => {
    render(
      <CopilotChatProvider {...getCopilotChatProviderProps()} topic={undefined} threadId="3" mode="immersive">
        <ContentPreviewProvider>
          <TimelineEvents
            message={{
              id: '12',
              role: 'assistant',
              createdAt: '2020-01-01T00:00:00Z',
              threadID: '12',
              references: [
                {
                  type: 'text',
                  name: 'timeline-event: {"type": "switch-issue-template", "markdownContent": "Removing template…"}',
                },
                {
                  type: 'draft-issue',
                  tag: 'test-issue',
                  title: 'A new issue',
                } as DraftIssueReference,
              ],
              content: "Template changed to 'Bug Report'",
            }}
            messageIndex={2}
            isViewingSharedThread={false}
          />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    expect(await screen.findByText('A new issue')).toBeInTheDocument()
    expect(await screen.findByText('Removing template…')).toBeInTheDocument()
  })
})

describe('SituationalTimelineEvents', () => {
  describe('Shared thread cutoff message', () => {
    it('Renders when isLatestMessage is true', async () => {
      render(
        <TimelineEvents
          message={{
            id: '12',
            role: 'assistant',
            createdAt: '2020-01-01T00:00:00Z',
            threadID: '12',
            references: [],
            content: 'test',
          }}
          messageIndex={2}
          isViewingSharedThread={false}
          isSharedMessage
          isLatestMessage
        />,
      )

      expect(await screen.findByText('Messages up to this point are included in shared link')).toBeInTheDocument()
    })

    it('Renders when isLatestMessage is false', async () => {
      render(
        <TimelineEvents
          message={{
            id: '12',
            role: 'assistant',
            createdAt: '2020-01-01T00:00:00Z',
            threadID: '12',
            references: [],
            content: 'test',
          }}
          messageIndex={2}
          isViewingSharedThread={false}
          isSharedMessage
          isLatestMessage={false}
        />,
      )

      expect(await screen.findByText('Messages up to this point are included in shared link')).toBeInTheDocument()
    })

    it('Does not render when isSharedMessage is false', () => {
      render(
        <TimelineEvents
          message={{
            id: '12',
            role: 'assistant',
            createdAt: '2020-01-01T00:00:00Z',
            threadID: '12',
            references: [],
            content: 'test',
          }}
          messageIndex={2}
          isViewingSharedThread={false}
          isSharedMessage={false}
          isLatestMessage
        />,
      )

      expect(screen.queryByText('Messages up to this point are included in shared link')).not.toBeInTheDocument()
    })

    it('Does not render when isViewingSharedThread is true', () => {
      render(
        <TimelineEvents
          message={{
            id: '12',
            role: 'assistant',
            createdAt: '2020-01-01T00:00:00Z',
            threadID: '12',
            references: [],
            content: 'test',
          }}
          messageIndex={2}
          isViewingSharedThread
          isSharedMessage
          isLatestMessage
        />,
      )

      expect(screen.queryByText('Messages up to this point are included in shared link')).not.toBeInTheDocument()
    })
  })

  describe('Shared thread new private conversation message', () => {
    it('Renders when isSharedMessage is true', async () => {
      jest.spyOn(copilotFeatureFlags, 'copilotDuplicateThread', 'get').mockReturnValue(true)

      render(
        <TimelineEvents
          message={{
            id: '12',
            role: 'assistant',
            createdAt: '2020-01-01T00:00:00Z',
            threadID: '12',
            references: [],
            content: 'test',
          }}
          messageIndex={2}
          isViewingSharedThread
          isSharedMessage
          isLatestMessage
        />,
      )

      expect(
        await screen.findByText('Messages beyond this point will start a new private conversation'),
      ).toBeInTheDocument()
    })

    it('Renders when isSharedMessage is false', async () => {
      jest.spyOn(copilotFeatureFlags, 'copilotDuplicateThread', 'get').mockReturnValue(true)

      render(
        <TimelineEvents
          message={{
            id: '12',
            role: 'assistant',
            createdAt: '2020-01-01T00:00:00Z',
            threadID: '12',
            references: [],
            content: 'test',
          }}
          messageIndex={2}
          isViewingSharedThread
          isSharedMessage={false}
          isLatestMessage
        />,
      )

      expect(
        await screen.findByText('Messages beyond this point will start a new private conversation'),
      ).toBeInTheDocument()
    })

    it('Does not render when copilotDuplicateThread FF is false', () => {
      jest.spyOn(copilotFeatureFlags, 'copilotDuplicateThread', 'get').mockReturnValue(false)

      render(
        <TimelineEvents
          message={{
            id: '12',
            role: 'assistant',
            createdAt: '2020-01-01T00:00:00Z',
            threadID: '12',
            references: [],
            content: 'test',
          }}
          messageIndex={2}
          isViewingSharedThread
          isSharedMessage
          isLatestMessage
        />,
      )

      expect(
        screen.queryByText('Messages beyond this point will start a new private conversation'),
      ).not.toBeInTheDocument()
    })

    it('Does not render when isLatestMessage is false', () => {
      jest.spyOn(copilotFeatureFlags, 'copilotDuplicateThread', 'get').mockReturnValue(true)

      render(
        <TimelineEvents
          message={{
            id: '12',
            role: 'assistant',
            createdAt: '2020-01-01T00:00:00Z',
            threadID: '12',
            references: [],
            content: 'test',
          }}
          messageIndex={2}
          isViewingSharedThread
          isSharedMessage
          isLatestMessage={false}
        />,
      )

      expect(
        screen.queryByText('Messages beyond this point will start a new private conversation'),
      ).not.toBeInTheDocument()
    })

    it('Does not render when isViewingSharedThread is false', () => {
      jest.spyOn(copilotFeatureFlags, 'copilotDuplicateThread', 'get').mockReturnValue(true)

      render(
        <TimelineEvents
          message={{
            id: '12',
            role: 'assistant',
            createdAt: '2020-01-01T00:00:00Z',
            threadID: '12',
            references: [],
            content: 'test',
          }}
          messageIndex={2}
          isViewingSharedThread={false}
          isSharedMessage
          isLatestMessage
        />,
      )

      expect(
        screen.queryByText('Messages beyond this point will start a new private conversation'),
      ).not.toBeInTheDocument()
    })
  })
})

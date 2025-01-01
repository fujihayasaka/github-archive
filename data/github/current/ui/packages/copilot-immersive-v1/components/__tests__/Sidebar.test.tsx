import {getCopilotChatProviderProps, getDefaultReducerState} from '@github-ui/copilot-chat/test-utils/mock-data'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {CopilotChatProvider} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {ContentPreviewProvider} from '../ContentPreview/ContentPreviewContext'
import {Sidebar} from '../Sidebar'

describe('Spaces in Immersive Sidebar', () => {
  const timeNow = new Date(Date.now()).toISOString()
  const threads = new Map([
    ['2', {id: '2', name: 'Space thread 1', customCopilotID: 7, createdAt: timeNow, updatedAt: timeNow}],
    ['3', {id: '3', name: 'Not a space thread', createdAt: timeNow, updatedAt: timeNow}],
    ['4', {id: '4', name: 'Diff space thread', customCopilotID: 8, createdAt: timeNow, updatedAt: timeNow}],
  ])

  it('renders all threads not only those associated to the space', () => {
    jest.spyOn(copilotFeatureFlags, 'customCopilots', 'get').mockReturnValue(true)

    render(
      <CopilotChatProvider
        {...getCopilotChatProviderProps()}
        mode="immersive"
        threadId={null}
        testReducerState={{
          ...getDefaultReducerState('2', undefined, 'immersive'),
          topicLoading: {state: 'loaded', error: null},
          messagesLoading: {state: 'loaded', error: null},
          threads,
          customCopilotId: 7,
        }}
      >
        <ContentPreviewProvider>
          <Sidebar isVisible isPinned={false} isFloating={false} onNewThread={() => {}} onToggle={() => {}} />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    expect(screen.getByText('Space thread 1')).toBeInTheDocument()
    expect(screen.getByText('Not a space thread')).toBeInTheDocument()
    expect(screen.getByText('Diff space thread')).toBeInTheDocument()
  })

  it('show space threads if in a general conversation', () => {
    jest.spyOn(copilotFeatureFlags, 'customCopilots', 'get').mockReturnValue(true)

    render(
      <CopilotChatProvider
        {...getCopilotChatProviderProps()}
        mode="immersive"
        threadId={null}
        testReducerState={{
          ...getDefaultReducerState('3', undefined, 'immersive'),
          topicLoading: {state: 'loaded', error: null},
          messagesLoading: {state: 'loaded', error: null},
          threads,
        }}
      >
        <ContentPreviewProvider>
          <Sidebar isVisible isPinned={false} isFloating={false} onNewThread={() => {}} onToggle={() => {}} />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    expect(screen.getByText('Not a space thread')).toBeInTheDocument()
    expect(screen.getByText('Space thread 1')).toBeInTheDocument()
    expect(screen.getByText('Diff space thread')).toBeInTheDocument()
  })

  it('returns all threads if customCopilots is disabled', () => {
    jest.spyOn(copilotFeatureFlags, 'customCopilots', 'get').mockReturnValue(false)

    render(
      <CopilotChatProvider
        {...getCopilotChatProviderProps()}
        mode="immersive"
        threadId={null}
        testReducerState={{
          ...getDefaultReducerState('2', undefined, 'immersive'),
          topicLoading: {state: 'loaded', error: null},
          messagesLoading: {state: 'loaded', error: null},
          threads,
        }}
      >
        <ContentPreviewProvider>
          <Sidebar isVisible isPinned={false} isFloating={false} onNewThread={() => {}} onToggle={() => {}} />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    expect(screen.getByText('Not a space thread')).toBeInTheDocument()
    expect(screen.getByText('Space thread 1')).toBeInTheDocument()
    expect(screen.getByText('Diff space thread')).toBeInTheDocument()
  })
})

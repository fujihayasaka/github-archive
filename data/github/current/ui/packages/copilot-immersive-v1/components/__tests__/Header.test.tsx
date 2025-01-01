import {mockClientEnv} from '@github-ui/client-env/mock'
import {getCopilotChatProviderProps, getDefaultReducerState} from '@github-ui/copilot-chat/test-utils/mock-data'
import type {CopilotChatState} from '@github-ui/copilot-chat/utils/copilot-chat-reducer'
import type {CopilotChatRepo, CopilotCustomInstructions} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {copilotLocalStorage} from '@github-ui/copilot-chat/utils/copilot-local-storage'
import {CopilotChatProvider, type CopilotChatProviderProps} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {screen} from '@testing-library/react'

import {useIsSharedThread} from '../../hooks/use-is-shared-thread'
import {ContentPreviewProvider} from '../ContentPreview/ContentPreviewContext'
import {Header} from '../Header'

type Threads = Map<
  string,
  {
    id: string
    sharedID: string
    name: string
    createdAt: string
    updatedAt: string
  }
>

const userEvent = setupUserEvent()

jest.mock('@github-ui/react-core/use-app-payload')
jest.mock('../../hooks/use-is-shared-thread')
jest.mocked(useAppPayload).mockReturnValue({
  copilotChatSettingEnabled: true,
  ssoOrganizations: [],
  apiURL: '',
  canShareThread: true,
})

const mockUseIsSharedThread = jest.mocked(useIsSharedThread)

const defaultThreads: Threads = new Map([
  [
    'thread-1',
    {
      id: 'thread-1',
      sharedID: 'thread-1-shared',
      name: 'Default Thread',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    },
  ],
])

function getThreadReducerState(threads: Threads, viewingThread?: boolean): CopilotChatState {
  return {
    ...getDefaultReducerState(viewingThread ? 'thread-1' : '2', undefined, 'immersive'),
    messagesLoading: {state: 'loaded' as const, error: null},
    threads, // Add threads to test state
  }
}

const defaultProviderProps = getCopilotChatProviderProps()

function TestHeaderSetup({
  showModelPicker = true,
  showPreviewPaneButton = true,
  viewingThread = false,
  selectedThreadID = 'thread-1',
  threads = defaultThreads,
  providerProps = defaultProviderProps,
  omitReducerState = false,
}) {
  const mockProviderProps = {
    ...providerProps,
    selectedThreadID,
  }

  return (
    <CopilotChatProvider
      {...mockProviderProps}
      mode="immersive"
      threadId={viewingThread ? selectedThreadID : null}
      testReducerState={omitReducerState ? undefined : getThreadReducerState(threads, viewingThread)}
    >
      <ContentPreviewProvider>
        <Header showModelPicker={showModelPicker} showPreviewPaneButton={showPreviewPaneButton} />
      </ContentPreviewProvider>
    </CopilotChatProvider>
  )
}

describe('Share button visibility', () => {
  beforeEach(() => {
    jest.clearAllMocks()
    mockUseIsSharedThread.mockReturnValue(false)
  })

  describe('with feature flag disabled', () => {
    it('shows standalone share button with default setup', () => {
      render(<TestHeaderSetup />)
      expect(screen.getByRole('button', {name: 'This conversation has not yet been shared'})).toBeInTheDocument()
      expect(screen.queryByTestId('manage-shared-conversations')).not.toBeInTheDocument()
    })

    it('should not show ShareConversationButton when thread is a shared thread', () => {
      mockUseIsSharedThread.mockReturnValue(true)

      render(<TestHeaderSetup />)

      expect(screen.queryByRole('button', {name: 'Share conversation'})).not.toBeInTheDocument()
    })

    it('should not show ShareConversationButton when canShareThread is false', () => {
      jest.mocked(useAppPayload).mockReturnValue({
        canShareThread: false,
      })

      render(<TestHeaderSetup />)

      expect(screen.queryByRole('button', {name: 'Share conversation'})).not.toBeInTheDocument()
    })

    it('should not show ShareConversationButton when messages are still loading', () => {
      render(
        <CopilotChatProvider
          {...{
            ...getCopilotChatProviderProps(),
            selectedThreadID: 'thread-1',
          }}
          mode="immersive"
          threadId={null}
          testReducerState={{
            ...getDefaultReducerState('2', undefined, 'immersive'),
            messagesLoading: {state: 'loading', error: null},
          }}
        >
          <ContentPreviewProvider>
            <Header />
          </ContentPreviewProvider>
        </CopilotChatProvider>,
      )

      expect(screen.queryByRole('button', {name: 'Share conversation'})).not.toBeInTheDocument()
    })

    it('should not show ShareConversationButton when thread is associated with a space', () => {
      render(
        <CopilotChatProvider
          {...{
            ...getCopilotChatProviderProps(),
            selectedThreadID: 'thread-1',
          }}
          mode="immersive"
          threadId={null}
          testReducerState={{
            ...getDefaultReducerState('2', undefined, 'immersive'),
            threads: new Map([
              [
                'thread-1',
                {
                  id: 'thread-1',
                  name: 'Default Thread',
                  createdAt: new Date().toISOString(),
                  updatedAt: new Date().toISOString(),
                  customCopilotID: 123,
                },
              ],
            ]),
          }}
        >
          <ContentPreviewProvider>
            <Header />
          </ContentPreviewProvider>
        </CopilotChatProvider>,
      )

      expect(screen.queryByRole('button', {name: 'Share conversation'})).not.toBeInTheDocument()
    })
  })

  describe('with feature flag enabled', () => {
    beforeEach(() => {
      // Ensure test has required mocks
      jest.mocked(useAppPayload).mockReturnValue({
        copilotChatSettingEnabled: true,
        ssoOrganizations: [],
        apiURL: '',
        canShareThread: true,
      })
      mockUseIsSharedThread.mockReturnValue(false)
    })

    it('shows button group with both buttons', () => {
      render(<TestHeaderSetup viewingThread />)

      const buttonGroup = screen.getByTestId('manage-shared-conversations')
      expect(buttonGroup).toBeInTheDocument()
      expect(screen.getByRole('button', {name: 'Anyone with the link can view this conversation'})).toBeInTheDocument()
      expect(screen.getByRole('button', {name: 'Additional share options'})).toBeInTheDocument()
    })
  })
})

describe('Custom Instructions', () => {
  let chatProviderProps: CopilotChatProviderProps
  let mockRepoCustomInstructions: CopilotCustomInstructions

  beforeEach(() => {
    mockClientEnv({
      featureFlags: ['copilot_chat_repo_custom_instructions'],
    })
    chatProviderProps = getCopilotChatProviderProps()
    chatProviderProps.chatIsOpen = true

    mockRepoCustomInstructions = {type: 'Repository', prompt: 'beep boop', owner: 'github/github'}
    ;(chatProviderProps.topic as CopilotChatRepo).customInstructions = [mockRepoCustomInstructions]
    copilotLocalStorage.setRepoCustomInstructionsState(true)

    jest.clearAllMocks()
  })

  test('render disable link if custom instructions is feature enabled', async () => {
    ;(chatProviderProps.topic as CopilotChatRepo).customInstructions = [mockRepoCustomInstructions]
    render(<TestHeaderSetup omitReducerState providerProps={chatProviderProps} />)

    await userEvent.click(screen.getByRole('button', {name: 'Menu'}))
    expect(await screen.findByText('Disable custom instructions')).toBeInTheDocument()
  })

  test('render enable link if custom instructions is feature enabled', async () => {
    ;(chatProviderProps.topic as CopilotChatRepo).customInstructions = [mockRepoCustomInstructions]
    copilotLocalStorage.setRepoCustomInstructionsState(false)
    render(<TestHeaderSetup omitReducerState providerProps={chatProviderProps} />)

    await userEvent.click(screen.getByRole('button', {name: 'Menu'}))
    expect(await screen.findByText('Enable custom instructions')).toBeInTheDocument()
  })

  test('render disable link if custom instructions is preview feature enabled', async () => {
    jest.spyOn(copilotFeatureFlags, 'repoCustomInstructionsPreview', 'get').mockReturnValue(true)
    copilotLocalStorage.setRepoCustomInstructionsState(true)
    render(<TestHeaderSetup omitReducerState providerProps={chatProviderProps} />)

    await userEvent.click(screen.getByRole('button', {name: 'Menu'}))
    expect(await screen.findByText('Disable custom instructions')).toBeInTheDocument()
  })

  test('do not render link if custom instructions is empty', async () => {
    ;(chatProviderProps.topic as CopilotChatRepo).customInstructions = []
    jest.spyOn(copilotFeatureFlags, 'repoCustomInstructionsPreview', 'get').mockReturnValue(true)
    copilotLocalStorage.setRepoCustomInstructionsState(true)
    render(<TestHeaderSetup omitReducerState providerProps={chatProviderProps} />)

    await userEvent.click(screen.getByRole('button', {name: 'Menu'}))
    expect(screen.queryByText('Disable custom instructions')).not.toBeInTheDocument()
  })

  test('render link if topics as reference is enabled', async () => {
    jest.spyOn(copilotFeatureFlags, 'repoCustomInstructionsPreview', 'get').mockReturnValue(true)
    jest.spyOn(copilotFeatureFlags, 'topicsAsReferences', 'get').mockReturnValue(true)

    copilotLocalStorage.setRepoCustomInstructionsState(true)
    render(<TestHeaderSetup omitReducerState providerProps={chatProviderProps} />)

    await userEvent.click(screen.getByRole('button', {name: 'Menu'}))
    expect(screen.getByText('Disable custom instructions')).toBeInTheDocument()
  })
})

describe('Page title', () => {
  beforeEach(() => {
    jest.clearAllMocks()
    mockUseIsSharedThread.mockReturnValue(false)
  })

  test('shows new conversation title when looking at main copilot page', () => {
    render(<TestHeaderSetup viewingThread={false} />)

    expect(document.title).toBe('New conversation · GitHub Copilot')
  })

  test('shows shared conversation title when thread is shared', () => {
    mockUseIsSharedThread.mockReturnValue(true)

    render(<TestHeaderSetup />)

    expect(document.title).toBe('Shared conversation · GitHub Copilot')
  })

  test('shows thread name in title when looking at a thread', () => {
    render(<TestHeaderSetup viewingThread />)
    expect(document.title).toBe('Default Thread · GitHub Copilot')
  })
})

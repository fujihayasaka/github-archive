import {mockClientEnv} from '@github-ui/client-env/mock'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {
  getCopilotChatProviderProps,
  getMessageMock,
  getReducerStateMock,
  getRepositoryReferenceMock,
  getSymbolReferenceMock,
} from '../../test-utils/mock-data'
import type {GeneratedSuggestion} from '../../utils/copilot-chat-types'
import {CopilotChatProvider} from '../../utils/CopilotChatContext'
import CopilotSuggestions from '../CopilotSuggestions'

const mockSendChatMessage = jest.fn()
jest.mock('@github-ui/copilot-chat/CopilotChatManagerContext', () => ({
  ...jest.requireActual('@github-ui/copilot-chat/CopilotChatManagerContext'),
  useChatManager: () => ({
    sendChatMessage: mockSendChatMessage,
    getSelectedThread: jest.fn(),
  }),
}))

describe('CopilotSuggestions', () => {
  beforeEach(() => {
    jest.clearAllMocks()
  })

  it('should render the suggestions', () => {
    render(
      <CopilotChatProvider
        {...getCopilotChatProviderProps()}
        testReducerState={{
          ...getReducerStateMock(),
          suggestions: {
            referenceType: 'repository',
            suggestions: [
              {question: 'What is a pull request?'},
              {question: 'What is a repository?'},
              {question: 'What is the meaning of life?'},
            ],
          },
        }}
      >
        <CopilotSuggestions suggestionKind="initial" />
      </CopilotChatProvider>,
    )

    expect(screen.getByText('Ask about the repository:')).toBeInTheDocument()
    expect(screen.getByText('What is a pull request?')).toBeInTheDocument()
    expect(screen.getByText('What is a repository?')).toBeInTheDocument()
    expect(screen.getByText('What is the meaning of life?')).toBeInTheDocument()
  })

  it('should not render if there are no suggestions', () => {
    const {container} = render(
      <CopilotChatProvider
        {...getCopilotChatProviderProps()}
        testReducerState={{
          ...getReducerStateMock(),
          suggestions: null,
        }}
      >
        <CopilotSuggestions />
      </CopilotChatProvider>,
    )

    expect(container).toBeEmptyDOMElement()
  })

  it('should not render if the topic picker is visible', () => {
    const {container} = render(
      <CopilotChatProvider
        {...getCopilotChatProviderProps()}
        testReducerState={{
          ...getReducerStateMock(),
          suggestions: {
            referenceType: 'repository',
            suggestions: [
              {question: 'What is a pull request?'},
              {question: 'What is a repository?'},
              {question: 'What is the meaning of life?'},
            ],
          },
          showTopicPicker: true,
        }}
      >
        <CopilotSuggestions />
      </CopilotChatProvider>,
    )

    expect(container).toBeEmptyDOMElement()
  })

  describe('copilot_topics_as_references disabled', () => {
    it('should not render if there are any attached references', () => {
      const {container} = render(
        <CopilotChatProvider
          {...getCopilotChatProviderProps()}
          testReducerState={{
            ...getReducerStateMock(),
            suggestions: {
              referenceType: 'repository',
              suggestions: [
                {question: 'What is a pull request?'},
                {question: 'What is a repository?'},
                {question: 'What is the meaning of life?'},
              ],
            },
            currentReferences: [getRepositoryReferenceMock()],
          }}
        >
          <CopilotSuggestions />
        </CopilotChatProvider>,
      )

      expect(container).toBeEmptyDOMElement()
    })
  })

  describe('copilot_topics_as_references enabled', () => {
    beforeEach(() => {
      mockClientEnv({
        featureFlags: ['copilot_topics_as_references'],
      })
    })

    it('should render if the only attached reference is the current repository', () => {
      const {container} = render(
        <CopilotChatProvider
          {...getCopilotChatProviderProps()}
          testReducerState={{
            ...getReducerStateMock(),
            suggestions: {
              referenceType: 'repository',
              suggestions: [
                {question: 'What is a pull request?'},
                {question: 'What is a repository?'},
                {question: 'What is the meaning of life?'},
              ],
            },
            currentRepository: getRepositoryReferenceMock(),
            currentReferences: [getRepositoryReferenceMock(), getSymbolReferenceMock()],
          }}
        >
          <CopilotSuggestions />
        </CopilotChatProvider>,
      )

      expect(container).toBeEmptyDOMElement()
    })

    it('should not render if the current repository is not attached', () => {
      const {container} = render(
        <CopilotChatProvider
          {...getCopilotChatProviderProps()}
          testReducerState={{
            ...getReducerStateMock(),
            suggestions: {
              referenceType: 'repository',
              suggestions: [
                {question: 'What is a pull request?'},
                {question: 'What is a repository?'},
                {question: 'What is the meaning of life?'},
              ],
            },
            currentRepository: getRepositoryReferenceMock(),
            currentReferences: [],
          }}
        >
          <CopilotSuggestions />
        </CopilotChatProvider>,
      )

      expect(container).toBeEmptyDOMElement()
    })

    it('should not render if there are any attached references other than the current repository', () => {
      const {container} = render(
        <CopilotChatProvider
          {...getCopilotChatProviderProps()}
          testReducerState={{
            ...getReducerStateMock(),
            suggestions: {
              referenceType: 'repository',
              suggestions: [
                {question: 'What is a pull request?'},
                {question: 'What is a repository?'},
                {question: 'What is the meaning of life?'},
              ],
            },
            currentRepository: getRepositoryReferenceMock(),
            currentReferences: [getRepositoryReferenceMock(), getSymbolReferenceMock()],
          }}
        >
          <CopilotSuggestions />
        </CopilotChatProvider>,
      )

      expect(container).toBeEmptyDOMElement()
    })
  })

  it('should not render if messages are being loaded', () => {
    const {container} = render(
      <CopilotChatProvider
        {...getCopilotChatProviderProps()}
        testReducerState={{
          ...getReducerStateMock(),
          suggestions: {
            referenceType: 'repository',
            suggestions: [
              {question: 'What is a pull request?'},
              {question: 'What is a repository?'},
              {question: 'What is the meaning of life?'},
            ],
          },
          messagesLoading: {state: 'loading', error: null},
        }}
      >
        <CopilotSuggestions />
      </CopilotChatProvider>,
    )

    expect(container).toBeEmptyDOMElement()
  })

  it('should not render if copilot is currently streaming', () => {
    const {container} = render(
      <CopilotChatProvider
        {...getCopilotChatProviderProps()}
        testReducerState={{
          ...getReducerStateMock(),
          suggestions: {
            referenceType: 'repository',
            suggestions: [
              {question: 'What is a pull request?'},
              {question: 'What is a repository?'},
              {question: 'What is the meaning of life?'},
            ],
          },
          streamingMessage: getMessageMock(),
        }}
      >
        <CopilotSuggestions />
      </CopilotChatProvider>,
    )

    expect(container).toBeEmptyDOMElement()
  })

  it('should send the selected suggestion', async () => {
    const {user} = render(
      <CopilotChatProvider
        {...getCopilotChatProviderProps()}
        testReducerState={{
          ...getReducerStateMock(),
          suggestions: {
            referenceType: 'repository',
            suggestions: [
              {question: 'What is a pull request?'},
              {question: 'What is a repository?'},
              {question: 'What is the meaning of life?'},
            ],
          },
        }}
      >
        <CopilotSuggestions />
      </CopilotChatProvider>,
    )

    const item = screen.getByText('What is the meaning of life?')
    expect(item).toBeInTheDocument()

    await user.click(item)

    expect(mockSendChatMessage).toHaveBeenCalledWith(
      expect.objectContaining({
        content: 'What is the meaning of life?',
        intent: undefined,
        modeOverride: undefined,
      }),
    )
  })

  it('should send the selected suggestion with applicable overrides', async () => {
    const suggestion: GeneratedSuggestion = {
      question: 'What is the meaning of life?',
      prompt: `
        This is a much more detailed text, more thoroughly explaining how
        Copilot should respond. It will be sent instead of the suggestion title.
      `,
      intent: 'conversation',
      mode: 'task-oriented-assistive',
    }

    const {user} = render(
      <CopilotChatProvider
        {...getCopilotChatProviderProps()}
        testReducerState={{
          ...getReducerStateMock(),
          suggestions: {
            referenceType: 'repository',
            suggestions: [suggestion],
          },
        }}
      >
        <CopilotSuggestions />
      </CopilotChatProvider>,
    )

    const item = screen.getByText('What is the meaning of life?')
    expect(item).toBeInTheDocument()

    await user.click(item)

    expect(mockSendChatMessage).toHaveBeenCalledWith(
      expect.objectContaining({
        content: suggestion.prompt,
        intent: suggestion.intent,
        modeOverride: suggestion.mode,
      }),
    )
  })
})

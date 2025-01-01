import {relayEnvironmentWithMissingFieldHandlerForNode} from '@github-ui/relay-environment'
import {shouldInteractionPlay} from '@github-ui/storybook'
import type {Meta, StoryObj} from '@storybook/react'
import {expect, userEvent, waitFor, within} from '@storybook/test'
import {RelayEnvironmentProvider} from 'react-relay'
import {BrowserRouter} from 'react-router-dom'

import {getCopilotChatProviderProps} from '../test-utils/mock-data'
import {CopilotChatProvider} from '../utils/CopilotChatContext'
import {
  copilotTokenMock,
  getAgentsHandler,
  getChatLinksHandler,
  getChatReferenceHandlerV2,
  getChatReferenceRepositoryHandler,
  getDiscussionSuggestionsHandler,
  getGraphqlQueryHandler,
  getIssueSuggestionsHandler,
  getKnowledgeBaseHandler,
  getPullRequestSuggestionsHandler,
  kbIndexedRepoMock,
} from './__tests__/utils/mock-network-calls'
import {ChatInput} from './ChatInput'
import {MenuPortalContainer} from './PortalContainerUtils'
import {TopicIndicator} from './TopicIndicator'

const meta: Meta<typeof ChatInput> = {
  title: 'Apps/Copilot/ChatInput',
  component: ChatInput,
  beforeEach: () => {
    // Erase all stored content in the local storage before each test to wipe out the network calls and stored issue data
    localStorage.clear()
    document.execCommand = () => {
      throw new Error(
        "execCommand is apparently incompatible with userEvent, so we don't use it in the storybook test environment. Since it's a deprecated API, consumers should gracefully handle thrown errors",
      )
    }
  },
  parameters: {
    msw: {
      handlers: [
        copilotTokenMock(),
        getGraphqlQueryHandler(10),
        getIssueSuggestionsHandler(10),
        getPullRequestSuggestionsHandler(10),
        getDiscussionSuggestionsHandler(10),
        getChatLinksHandler(10),
        getChatReferenceRepositoryHandler(10),
        getChatReferenceHandlerV2(10),
        getAgentsHandler(10),
      ],
    },
    a11y: {
      config: {
        rules: [
          {id: 'color-contrast', enabled: false}, // Currently the test fails for color contrast on the issue chip's Tooltip which is coming from Primer
        ],
      },
    },
    test: {
      dangerouslyIgnoreUnhandledErrors: true, // Not great, but it doesn't seem there's a way to swallow a specific error
    },
  },
}

const isElementInOverflow = (element: HTMLElement, container: HTMLElement): boolean => {
  const elementRect = element.getBoundingClientRect()
  const containerRect = container.getBoundingClientRect()

  return (
    elementRect.left < containerRect.left ||
    elementRect.right > containerRect.right ||
    elementRect.top < containerRect.top ||
    elementRect.bottom > containerRect.bottom
  )
}

const environment = relayEnvironmentWithMissingFieldHandlerForNode()

export const Default: StoryObj<typeof ChatInput> = {
  render: () => {
    return (
      <BrowserRouter>
        <RelayEnvironmentProvider environment={environment}>
          <CopilotChatProvider {...getCopilotChatProviderProps()}>
            <div style={{position: 'absolute', bottom: '1em', left: '1em', right: '1em'}}>
              <ChatInput />
            </div>
          </CopilotChatProvider>
        </RelayEnvironmentProvider>
      </BrowserRouter>
    )
  },
}

export const AutocompleteRepoReference: StoryObj<typeof ChatInput> = {
  parameters: {
    enabledFeatures: ['copilot_chat_autocomplete'],
  },
  render: () => {
    return (
      <BrowserRouter>
        <RelayEnvironmentProvider environment={environment}>
          <CopilotChatProvider {...getCopilotChatProviderProps()}>
            <ChatInput />
          </CopilotChatProvider>
        </RelayEnvironmentProvider>
      </BrowserRouter>
    )
  },
  play: async ({context}) => {
    if (shouldInteractionPlay()) {
      const {canvasElement} = context
      const canvas = within(canvasElement)
      // eslint-disable-next-line @typescript-eslint/no-unnecessary-type-assertion
      const textArea = canvas.getByTestId('copilot-chat-input-textarea') as HTMLTextAreaElement
      const preview = canvas.getByTestId('copilot-chat-input-textarea-preview')

      await userEvent.click(textArea)
      await userEvent.type(textArea, 'I want this repo: @')

      const selectionType = canvas.getByRole('menuitem', {name: 'Repositories'})
      await waitFor(async () => {
        await expect(selectionType).toBeVisible()
      })
      await userEvent.click(selectionType)

      const selectionRepo = await waitFor(() => canvas.getByRole('menuitem', {name: 'github/copilot-chat'}))
      await userEvent.click(selectionRepo)

      await waitFor(
        async () => {
          await expect(preview).toHaveTextContent('I want this repo: @github/copilot-chat')
          await expect(textArea).toHaveTextContent('I want this repo: @github/copilot-chat')
          await expect(canvas.getByRole('link', {name: 'github/copilot-chat'})).toBeVisible()
          await expect(canvas.getByTestId('input-preview-ref')).toBeInTheDocument()
        },
        {timeout: 1500},
      )
    }
  },
}

export const CanEditInputReferenceText: StoryObj<typeof ChatInput> = {
  render: () => {
    return (
      <BrowserRouter>
        <RelayEnvironmentProvider environment={environment}>
          <CopilotChatProvider {...getCopilotChatProviderProps()}>
            <ChatInput />
          </CopilotChatProvider>
        </RelayEnvironmentProvider>
      </BrowserRouter>
    )
  },
  play: async ({context}) => {
    if (shouldInteractionPlay()) {
      const {canvasElement, step} = context
      const canvas = within(canvasElement)
      // eslint-disable-next-line @typescript-eslint/no-unnecessary-type-assertion
      const textArea = canvas.getByTestId('copilot-chat-input-textarea') as HTMLTextAreaElement
      const preview = canvas.getByTestId('copilot-chat-input-textarea-preview')

      await step('loads issue ref chip', async () => {
        await userEvent.click(textArea)
        await userEvent.type(textArea, 'I want to find this issue: ')
        await userEvent.paste(`${window.location.origin}/github/copilot-chat/issues/1234`)

        await expect(textArea).toHaveTextContent('I want to find this issue: @github/copilot-chat/issues/1234')
        await expect(preview).toHaveTextContent('I want to find this issue: @github/copilot-chat/issues/1234')

        const loading = canvas.getByTestId('loading-indicator')
        await expect(loading).toBeInTheDocument()

        await waitFor(
          async () => {
            await expect(preview).toHaveTextContent('I want to find this issue: @github/copilot-chat/issues/1234')
            await expect(textArea).toHaveTextContent('I want to find this issue: @github/copilot-chat/issues/1234')
            await expect(canvas.getByRole('link', {name: 'This is a test issue'})).toBeVisible()
            await expect(canvas.getByTestId('input-preview-ref')).toBeInTheDocument()
          },
          {timeout: 1500},
        )
      })

      await step('add text on new line', async () => {
        // click shift enter to add a new line
        await userEvent.keyboard('{Shift>}{Enter}{/Shift}')
        await userEvent.type(textArea, 'adding a new line below')

        await expect(preview).toHaveTextContent(
          'I want to find this issue: @github/copilot-chat/issues/1234 adding a new line',
        )
        await expect(textArea).toHaveTextContent(
          'I want to find this issue: @github/copilot-chat/issues/1234 adding a new line below',
        )
        await expect(canvas.getByTestId('input-preview-ref')).toBeInTheDocument()
        await expect(canvas.getByRole('link', {name: 'This is a test issue'})).toBeVisible()
      })

      const index = 'I want to find this issue: @github/copilot-chat/'.length
      textArea.setSelectionRange(index, index)
      await userEvent.keyboard('editing the reference/')

      await step('should keep issue ref chip', async () => {
        await expect(preview).toHaveTextContent(
          'I want to find this issue: @github/copilot-chat/editing the reference/issues/1234',
        )
        await expect(textArea).toHaveTextContent(
          'I want to find this issue: @github/copilot-chat/editing the reference/issues/1234',
        )
      })
    }
  },
}

export const KeepIssueReferencesWhenChangingTopic: StoryObj<typeof ChatInput> = {
  parameters: {
    msw: {
      handlers: [...meta.parameters?.msw?.handlers, getKnowledgeBaseHandler(100), kbIndexedRepoMock()],
    },
  },
  render: () => {
    return (
      <BrowserRouter>
        <RelayEnvironmentProvider environment={environment}>
          <CopilotChatProvider {...getCopilotChatProviderProps()}>
            <MenuPortalContainer />
            <TopicIndicator />
            <ChatInput />
          </CopilotChatProvider>
        </RelayEnvironmentProvider>
      </BrowserRouter>
    )
  },
  play: async ({context}) => {
    if (shouldInteractionPlay()) {
      const {canvasElement, step} = context
      const canvas = within(canvasElement)
      const textArea = canvas.getByTestId('copilot-chat-input-textarea')
      const preview = canvas.getByTestId('copilot-chat-input-textarea-preview')

      await step('loads issue ref chip', async () => {
        await userEvent.click(textArea)
        await userEvent.type(textArea, 'I want to find this issue: ')
        await userEvent.paste(`${window.location.origin}/github/copilot-chat/issues/1234`)

        await expect(textArea).toHaveTextContent('I want to find this issue: @github/copilot-chat/issues/1234')
        await expect(preview).toHaveTextContent('I want to find this issue: @github/copilot-chat/issues/1234')

        const loading = canvas.getByTestId('loading-indicator')
        await expect(loading).toBeInTheDocument()

        await waitFor(
          async () => {
            await expect(preview).toHaveTextContent('I want to find this issue: @github/copilot-chat/issues/1234')
            await expect(textArea).toHaveTextContent('I want to find this issue: @github/copilot-chat/issues/1234')
            await expect(canvas.getByRole('link', {name: 'This is a test issue'})).toBeVisible()
            await expect(canvas.getByTestId('input-preview-ref')).toBeInTheDocument()
          },
          {timeout: 1500},
        )
      })

      await step('should change topic', async () => {
        const attachmentButton = canvas.getByTestId('attachment-menu-button')
        await userEvent.click(attachmentButton)
        const knowledgeOption = canvas.getByRole('menuitem', {name: /Knowledge/i})
        await userEvent.click(knowledgeOption)

        await waitFor(() => expect(canvas.queryByText('Fetching knowledge bases…')).not.toBeInTheDocument())

        const kbList = canvas.getByRole('dialog')
        const firstKb = await within(kbList).findByText('GitHub Engineering')

        await waitFor(() => expect(firstKb).not.toHaveAttribute('aria-disabled', 'true'))

        await userEvent.click(firstKb)

        await userEvent.click(canvas.getByRole('button', {name: /Save/i}))

        await waitFor(() => expect(firstKb).not.toBeInTheDocument())
      })

      await step('should keep issue ref chip', async () => {
        await expect(preview).toHaveTextContent('I want to find this issue: @github/copilot-chat/issues/1234')
        await expect(textArea).toHaveTextContent('I want to find this issue: @github/copilot-chat/issues/1234')
        await expect(canvas.getByRole('link', {name: 'This is a test issue'})).toBeVisible()
        await expect(canvas.getByTestId('input-preview-ref')).toBeInTheDocument()
      })
    }
  },
}

export const PasteReferenceWithinText: StoryObj<typeof ChatInput> = {
  render: () => {
    return (
      <BrowserRouter>
        <RelayEnvironmentProvider environment={environment}>
          <CopilotChatProvider {...getCopilotChatProviderProps()}>
            <ChatInput />
          </CopilotChatProvider>
        </RelayEnvironmentProvider>
      </BrowserRouter>
    )
  },
  play: async ({context}) => {
    if (shouldInteractionPlay()) {
      const {canvasElement, step} = context
      const canvas = within(canvasElement)
      // eslint-disable-next-line @typescript-eslint/no-unnecessary-type-assertion
      const textArea = canvas.getByTestId('copilot-chat-input-textarea') as HTMLTextAreaElement
      const preview = canvas.getByTestId('copilot-chat-input-textarea-preview')

      await step('should add reference when text pasted', async () => {
        await userEvent.click(textArea)
        await userEvent.paste(`${window.location.origin}/github/copilot-chat/issues/1234`)

        await expect(textArea).toHaveTextContent('@github/copilot-chat/issues/1234')
        await expect(preview).toHaveTextContent('@github/copilot-chat/issues/1234')

        const loading = canvas.getByTestId('loading-indicator')
        await expect(loading).toBeInTheDocument()

        await waitFor(
          async () => {
            await expect(preview).toHaveTextContent('@github/copilot-chat/issues/1234')
            await expect(textArea).toHaveTextContent('@github/copilot-chat/issues/1234')
            await expect(canvas.getByRole('link', {name: 'This is a test issue'})).toBeVisible()
            await expect(canvas.getByTestId('input-preview-ref')).toBeInTheDocument()
          },
          {timeout: 1500},
        )
      })

      await userEvent.type(textArea, ' this text will be replaced')
      await expect(textArea).toHaveTextContent('@github/copilot-chat/issues/1234 this text will be replaced')

      const index = '@github/copilot-chat/issues/1234 this text'.length
      textArea.setSelectionRange(index - 'text'.length, index)
      await userEvent.paste(`${window.location.origin}/github/copilot-chat/issues/1234`)

      await expect(preview).toHaveTextContent(
        '@github/copilot-chat/issues/1234 this @github/copilot-chat/issues/1234 will be replaced',
      )
      await expect(textArea).toHaveTextContent(
        '@github/copilot-chat/issues/1234 this @github/copilot-chat/issues/1234 will be replaced',
      )
    }
  },
}

export const RemoveIssueReferenceByChip: StoryObj<typeof ChatInput> = {
  parameters: {
    title: 'Remove issue reference when chip removed',
  },
  render: () => {
    return (
      <BrowserRouter>
        <RelayEnvironmentProvider environment={environment}>
          <CopilotChatProvider {...getCopilotChatProviderProps()}>
            <ChatInput />
          </CopilotChatProvider>
        </RelayEnvironmentProvider>
      </BrowserRouter>
    )
  },
  play: async ({context}) => {
    if (shouldInteractionPlay()) {
      const {canvasElement, step} = context
      const canvas = within(canvasElement)

      await step('should remove the highlight from an issue reference when related chip is removed', async () => {
        const textArea = canvas.getByTestId('copilot-chat-input-textarea')
        const preview = canvas.getByTestId('copilot-chat-input-textarea-preview')

        await userEvent.click(textArea)
        await userEvent.type(textArea, 'I want to find this issue: ')
        await userEvent.paste(`${window.location.origin}/github/copilot-chat/issues/1234`)

        await expect(textArea).toHaveTextContent('I want to find this issue: @github/copilot-chat/issues/1234')
        await expect(preview).toHaveTextContent('I want to find this issue: @github/copilot-chat/issues/1234')

        const loading = canvas.getByTestId('loading-indicator')
        await expect(loading).toBeInTheDocument()

        await waitFor(
          async () => {
            await expect(preview).toHaveTextContent('I want to find this issue: @github/copilot-chat/issues/1234')
            await expect(textArea).toHaveTextContent('I want to find this issue: @github/copilot-chat/issues/1234')
            await expect(canvas.getByRole('link', {name: 'This is a test issue'})).toBeVisible()
            await expect(canvas.getByTestId('input-preview-ref')).toBeInTheDocument()
          },
          {timeout: 1500},
        )

        const issueChip = canvas.getByRole('link', {name: 'This is a test issue'})
        issueChip.focus()
        await userEvent.keyboard('{Backspace}')

        await expect(issueChip).not.toBeInTheDocument()
        await expect(canvas.queryByTestId('input-preview-ref')).not.toBeInTheDocument()
        await expect(textArea).toHaveTextContent('I want to find this issue: @github/copilot-chat/issues/1234')
        await expect(preview).toHaveTextContent('I want to find this issue: @github/copilot-chat/issues/1234')
      })
    }
  },
}

export const RemoveIssueReferenceByRemoveAllButton: StoryObj<typeof ChatInput> = {
  parameters: {
    title: 'Remove issue reference when "Remove references" button pressed',
  },
  render: () => {
    return (
      <BrowserRouter>
        <RelayEnvironmentProvider environment={environment}>
          <CopilotChatProvider {...getCopilotChatProviderProps()}>
            <ChatInput />
          </CopilotChatProvider>
        </RelayEnvironmentProvider>
      </BrowserRouter>
    )
  },
  play: async ({context}) => {
    if (shouldInteractionPlay()) {
      const {canvasElement, step} = context
      const canvas = within(canvasElement)

      await step(
        'should remove the highlight from an issue reference when "remove attachments" button pressed',
        async () => {
          const textArea = canvas.getByTestId('copilot-chat-input-textarea')
          const preview = canvas.getByTestId('copilot-chat-input-textarea-preview')

          await userEvent.click(textArea)
          await userEvent.type(textArea, 'I want to find this issue: ')
          await userEvent.paste(`${window.location.origin}/github/copilot-chat/issues/1234`)

          await expect(textArea).toHaveTextContent('I want to find this issue: @github/copilot-chat/issues/1234')
          await expect(preview).toHaveTextContent('I want to find this issue: @github/copilot-chat/issues/1234')

          const loading = canvas.getByTestId('loading-indicator')
          await expect(loading).toBeInTheDocument()

          await waitFor(
            async () => {
              await expect(preview).toHaveTextContent('I want to find this issue: @github/copilot-chat/issues/1234')
              await expect(textArea).toHaveTextContent('I want to find this issue: @github/copilot-chat/issues/1234')
              await expect(canvas.getByRole('link', {name: 'This is a test issue'})).toBeVisible()
              await expect(canvas.getByTestId('input-preview-ref')).toBeInTheDocument()
            },
            {timeout: 1500},
          )

          const attachmentOptionsButton = canvas.getByRole('button', {name: 'Attachments options'})
          await userEvent.click(attachmentOptionsButton)
          const removeAttachmentButton = canvas.getByRole('menuitem', {name: 'Remove attachments'})
          await userEvent.click(removeAttachmentButton)

          await expect(canvas.queryByRole('link', {name: 'This is a test issue'})).not.toBeInTheDocument()
          await expect(canvas.queryByTestId('input-preview-ref')).not.toBeInTheDocument()
          await expect(textArea).toHaveTextContent('I want to find this issue: @github/copilot-chat/issues/1234')
          await expect(preview).toHaveTextContent('I want to find this issue: @github/copilot-chat/issues/1234')
        },
      )
    }
  },
}

export const ScrollToReferenceWhenAdded: StoryObj<typeof ChatInput> = {
  render: () => {
    return (
      <div style={{width: '350px'}}>
        <BrowserRouter>
          <RelayEnvironmentProvider environment={environment}>
            <CopilotChatProvider {...getCopilotChatProviderProps()}>
              <ChatInput />
            </CopilotChatProvider>
          </RelayEnvironmentProvider>
        </BrowserRouter>
      </div>
    )
  },
  play: async ({context}) => {
    if (shouldInteractionPlay()) {
      const {canvasElement, step} = context
      const canvas = within(canvasElement)
      const textArea = canvas.getByTestId('copilot-chat-input-textarea')
      const preview = canvas.getByTestId('copilot-chat-input-textarea-preview')

      await step('should add first reference chip', async () => {
        await userEvent.click(textArea)
        await userEvent.type(textArea, 'I want to find this issue: ')
        await userEvent.paste(`${window.location.origin}/github/copilot-chat/issues/1234`)

        await waitFor(
          async () => {
            await expect(preview).toHaveTextContent('I want to find this issue: @github/copilot-chat/issues/1234')
            await expect(textArea).toHaveTextContent('I want to find this issue: @github/copilot-chat/issues/1234')
            await expect(canvas.getByRole('link', {name: 'This is a test issue'})).toBeVisible()
            await expect(canvas.getByTestId('input-preview-ref')).toBeInTheDocument()
          },
          {timeout: 1500},
        )
      })

      const toolbar = canvas.getByRole('toolbar', {name: 'Attachments'})

      await step('should add second reference chip', async () => {
        await userEvent.type(textArea, ' ')
        await userEvent.paste(`${window.location.origin}/github/copilot-chat/issues/12345`)

        await waitFor(
          async () => {
            await expect(preview).toHaveTextContent(
              'I want to find this issue: @github/copilot-chat/issues/1234 @github/copilot-chat/issues/12345',
            )
            await expect(textArea).toHaveTextContent(
              'I want to find this issue: @github/copilot-chat/issues/1234 @github/copilot-chat/issues/12345',
            )
            const references = within(toolbar).getAllByRole('link')
            await expect(references).toHaveLength(2)
            await expect(isElementInOverflow(references[1]!, toolbar)).toBe(true)
          },
          {timeout: 1500},
        )
      })

      await step('should scroll to second reference chip', async () => {
        await waitFor(
          async () => {
            const references = within(toolbar).getAllByRole('link')
            await expect(isElementInOverflow(references[1]!, toolbar)).toBe(false)
          },
          {timeout: 1500},
        )
      })
    }
  },
}

export const RemoveReferenceByText: StoryObj<typeof ChatInput> = {
  render: () => {
    return (
      <BrowserRouter>
        <RelayEnvironmentProvider environment={environment}>
          <CopilotChatProvider {...getCopilotChatProviderProps()}>
            <ChatInput />
          </CopilotChatProvider>
        </RelayEnvironmentProvider>
      </BrowserRouter>
    )
  },
  play: async ({context}) => {
    if (shouldInteractionPlay()) {
      const {canvasElement, step} = context
      const canvas = within(canvasElement)
      const textArea = canvas.getByTestId('copilot-chat-input-textarea')
      const preview = canvas.getByTestId('copilot-chat-input-textarea-preview')

      await step('should add reference when text pasted', async () => {
        await userEvent.click(textArea)
        await userEvent.type(textArea, 'I want to find this issue: ')
        await userEvent.paste(`${window.location.origin}/github/copilot-chat/issues/1234`)

        await expect(textArea).toHaveTextContent('I want to find this issue: @github/copilot-chat/issues/1234')
        await expect(preview).toHaveTextContent('I want to find this issue: @github/copilot-chat/issues/1234')

        const loading = canvas.getByTestId('loading-indicator')
        await expect(loading).toBeInTheDocument()

        await waitFor(
          async () => {
            await expect(preview).toHaveTextContent('I want to find this issue: @github/copilot-chat/issues/1234')
            await expect(textArea).toHaveTextContent('I want to find this issue: @github/copilot-chat/issues/1234')
            await expect(canvas.getByRole('link', {name: 'This is a test issue'})).toBeVisible()
            await expect(canvas.getByTestId('input-preview-ref')).toBeInTheDocument()
          },
          {timeout: 1500},
        )
      })

      const issueChip = canvas.getByRole('link', {name: 'This is a test issue'})

      await step('should keep reference when space typed', async () => {
        await userEvent.type(textArea, ' ')
        await expect(issueChip).toBeInTheDocument()
      })

      await step('should remove reference when text is altered', async () => {
        await userEvent.keyboard('{Backspace}{Backspace}')
        await expect(issueChip).not.toBeInTheDocument()
        await expect(canvas.queryByTestId('input-preview-ref')).not.toBeInTheDocument()
        await expect(textArea).toHaveTextContent('I want to find this issue: @github/copilot-chat/issues/123')
        await expect(preview).toHaveTextContent('I want to find this issue: @github/copilot-chat/issues/123')
      })
    }
  },
}

export default meta

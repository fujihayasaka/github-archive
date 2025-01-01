import {shouldInteractionPlay} from '@github-ui/storybook'
import {expect} from '@storybook/jest'
import type {Meta, StoryObj} from '@storybook/react'
import {userEvent, waitFor, within} from '@storybook/test'
import {BrowserRouter} from 'react-router-dom'

import {getCopilotChatProviderProps} from '../test-utils/mock-data'
import {CopilotChatProvider} from '../utils/CopilotChatContext'
import {
  copilotTokenMock,
  getIssueDetailsHandler,
  getKnowledgeBaseHandler,
  kbIndexedRepoMock,
} from './__tests__/utils/mock-network-calls'
import {ChatInput} from './ChatInput'
import {MenuPortalContainer} from './PortalContainerUtils'
import {TopicIndicator} from './TopicIndicator'

const meta: Meta<typeof ChatInput> = {
  title: 'Apps/Copilot/ChatInputV2',
  component: ChatInput,
}

export const Default: StoryObj<typeof ChatInput> = {
  parameters: {
    msw: {
      handlers: [getIssueDetailsHandler(1000)],
    },
    enabledFeatures: ['copilot_ui_refs'],
  },
  render: () => {
    return (
      <BrowserRouter>
        <CopilotChatProvider {...getCopilotChatProviderProps()}>
          <ChatInput />
        </CopilotChatProvider>
      </BrowserRouter>
    )
  },
}

export const RemoveIssueReferenceByChip: StoryObj<typeof ChatInput> = {
  beforeEach: () => {
    // Erase all stored content in the local storage before each test to wipe out the network calls and stored issue data
    localStorage.clear()
  },
  parameters: {
    msw: {
      handlers: [getIssueDetailsHandler(1000)],
    },
    enabledFeatures: ['copilot_ui_refs'],
    a11y: {
      config: {
        rules: [
          {id: 'color-contrast', enabled: false}, // Currently the test fails for color contrast on the issue chip's Tooltip which is coming from Primer
        ],
      },
    },
    title: 'Remove issue reference when chip removed',
    test: {
      dangerouslyIgnoreUnhandledErrors: true, // Not great, but it doesn't seem there's a way to swallow a specific error
    },
  },
  render: () => {
    return (
      <BrowserRouter>
        <CopilotChatProvider {...getCopilotChatProviderProps()}>
          <ChatInput />
        </CopilotChatProvider>
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
        await userEvent.paste('https://github.com/github/copilot-chat/issues/1234')

        await expect(textArea).toHaveTextContent(
          'I want to find this issue: https://github.com/github/copilot-chat/issues/1234',
        )
        await expect(preview).toHaveTextContent(
          'I want to find this issue: https://github.com/github/copilot-chat/issues/1234',
        )

        const loading = canvas.getByTestId('loading-indicator')
        await expect(loading).toBeInTheDocument()

        await waitFor(
          async () => {
            await expect(preview).toHaveTextContent('I want to find this issue: #1234')
            await expect(textArea).toHaveTextContent('I want to find this issue: #1234')
            await expect(canvas.getByRole('link', {name: 'This is a test issue'})).toBeVisible()
            await expect(canvas.getByTestId('issue-ref-link')).toBeInTheDocument()
          },
          {timeout: 1500},
        )

        const issueChip = canvas.getByRole('link', {name: 'This is a test issue'})
        issueChip.focus()
        await userEvent.keyboard('{Backspace}')

        await expect(issueChip).not.toBeInTheDocument()
        await expect(canvas.queryByTestId('issue-ref-link')).not.toBeInTheDocument()
        await expect(textArea).toHaveTextContent('I want to find this issue: #1234')
        await expect(preview).toHaveTextContent('I want to find this issue: #1234')
      })
    }
  },
}

export const RemoveIssueReferenceByRemoveAllButton: StoryObj<typeof ChatInput> = {
  beforeEach: () => {
    // Erase all stored content in the local storage before each test to wipe out the network calls and stored issue data
    localStorage.clear()
  },
  parameters: {
    msw: {
      handlers: [getIssueDetailsHandler(1000)],
    },
    enabledFeatures: ['copilot_ui_refs'],
    a11y: {
      config: {
        rules: [
          {id: 'color-contrast', enabled: false}, // Currently the test fails for color contrast on the issue chip's Tooltip which is coming from Primer
        ],
      },
    },
    title: 'Remove issue reference when "Remove references" button pressed',
    test: {
      dangerouslyIgnoreUnhandledErrors: true, // Not great, but it doesn't seem there's a way to swallow a specific error
    },
  },
  render: () => {
    return (
      <BrowserRouter>
        <CopilotChatProvider {...getCopilotChatProviderProps()}>
          <ChatInput />
        </CopilotChatProvider>
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
          await userEvent.paste('https://github.com/github/copilot-chat/issues/1234')

          await expect(textArea).toHaveTextContent(
            'I want to find this issue: https://github.com/github/copilot-chat/issues/1234',
          )
          await expect(preview).toHaveTextContent(
            'I want to find this issue: https://github.com/github/copilot-chat/issues/1234',
          )

          const loading = canvas.getByTestId('loading-indicator')
          await expect(loading).toBeInTheDocument()

          await waitFor(
            async () => {
              await expect(preview).toHaveTextContent('I want to find this issue: #1234')
              await expect(textArea).toHaveTextContent('I want to find this issue: #1234')
              await expect(canvas.getByRole('link', {name: 'This is a test issue'})).toBeVisible()
              await expect(canvas.getByTestId('issue-ref-link')).toBeInTheDocument()
            },
            {timeout: 1500},
          )

          const attachmentOptionsButton = canvas.getByRole('button', {name: 'Attachments options'})
          await userEvent.click(attachmentOptionsButton)
          const removeAttachmentButton = canvas.getByRole('menuitem', {name: 'Remove attachments'})
          await userEvent.click(removeAttachmentButton)

          await expect(canvas.queryByRole('link', {name: 'This is a test issue'})).not.toBeInTheDocument()
          await expect(canvas.queryByTestId('issue-ref-link')).not.toBeInTheDocument()
          await expect(textArea).toHaveTextContent('I want to find this issue: #1234')
          await expect(preview).toHaveTextContent('I want to find this issue: #1234')
        },
      )
    }
  },
}

export const KeepIssueReferencesWhenChangingTopic: StoryObj<typeof ChatInput> = {
  beforeEach: () => {
    // Erase all stored content in the local storage before each test to wipe out the network calls and stored issue data
    localStorage.clear()
  },
  parameters: {
    msw: {
      handlers: [getIssueDetailsHandler(1000), getKnowledgeBaseHandler(100), kbIndexedRepoMock(), copilotTokenMock()],
    },
    enabledFeatures: ['copilot_ui_refs'],
    a11y: {
      config: {
        rules: [
          {id: 'color-contrast', enabled: false}, // Currently the test fails for color contrast on the issue chip's Tooltip which is coming from Primer
        ],
      },
    },
    title: 'Remove issue reference when chip removed',
    test: {
      dangerouslyIgnoreUnhandledErrors: true, // Not great, but it doesn't seem there's a way to swallow a specific error
    },
  },
  render: () => {
    return (
      <BrowserRouter>
        <CopilotChatProvider {...getCopilotChatProviderProps()}>
          <MenuPortalContainer />
          <TopicIndicator />
          <ChatInput />
        </CopilotChatProvider>
      </BrowserRouter>
    )
  },
  play: async ({context}) => {
    if (shouldInteractionPlay()) {
      const {canvasElement, step} = context
      const canvas = within(canvasElement)

      await step('loads issue ref chip', async () => {
        const textArea = canvas.getByTestId('copilot-chat-input-textarea')
        const preview = canvas.getByTestId('copilot-chat-input-textarea-preview')

        await userEvent.click(textArea)
        await userEvent.type(textArea, 'I want to find this issue: ')
        await userEvent.paste('https://github.com/github/copilot-chat/issues/1234')

        await expect(textArea).toHaveTextContent(
          'I want to find this issue: https://github.com/github/copilot-chat/issues/1234',
        )
        await expect(preview).toHaveTextContent(
          'I want to find this issue: https://github.com/github/copilot-chat/issues/1234',
        )

        const loading = canvas.getByTestId('loading-indicator')
        await expect(loading).toBeInTheDocument()

        await waitFor(
          async () => {
            await expect(preview).toHaveTextContent('I want to find this issue: #1234')
            await expect(textArea).toHaveTextContent('I want to find this issue: #1234')
            await expect(canvas.getByRole('link', {name: 'This is a test issue'})).toBeVisible()
            await expect(canvas.getByTestId('issue-ref-link')).toBeInTheDocument()
          },
          {timeout: 1500},
        )
      })

      await step('should change topic', async () => {
        const attachmentButton = canvas.getByRole('button', {name: /Add attachment/i})
        await userEvent.click(attachmentButton)
        const knowledgeOption = canvas.getByRole('menuitem', {name: /Knowledge/i})
        await userEvent.click(knowledgeOption)

        await waitFor(() => expect(canvas.queryByText('Fetching knowledge bases…')).not.toBeInTheDocument())

        const kbList = within(canvas.getByTestId('knowledge-select-panel')).getByRole('dialog')
        const firstKb = within(kbList).getAllByRole('option')?.[0]

        await waitFor(() => expect(firstKb).not.toHaveAttribute('aria-disabled', 'true'))

        await userEvent.click(firstKb!)

        await waitFor(() => expect(firstKb).not.toBeInTheDocument())
      })

      await step('should keep issue ref chip', async () => {
        const textArea = canvas.getByTestId('copilot-chat-input-textarea')
        const preview = canvas.getByTestId('copilot-chat-input-textarea-preview')
        await expect(preview).toHaveTextContent('I want to find this issue: #1234')
        await expect(textArea).toHaveTextContent('I want to find this issue: #1234')
        await expect(canvas.getByRole('link', {name: 'This is a test issue'})).toBeVisible()
        await expect(canvas.getByTestId('issue-ref-link')).toBeInTheDocument()
      })
    }
  },
}

export default meta

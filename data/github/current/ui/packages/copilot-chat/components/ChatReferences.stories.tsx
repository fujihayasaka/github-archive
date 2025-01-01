import type {Meta} from '@storybook/react'

import {
  getCopilotChatProviderProps,
  getIssueReferenceMock,
  getPullRequestReferenceMock,
  getReferencesMock,
  getRepositoryReferenceMock,
  getSnippetReferenceMock,
  getSymbolReferenceMock,
} from '../test-utils/mock-data'
import {CopilotChatProvider} from '../utils/CopilotChatContext'
import type {ChatMessageReferencesListProps, ChatMessageReferenceTokensProps} from './ChatReferences'
import {
  ChatMessageReferencesList,
  ChatMessageReferenceTokens as ChatMessageReferenceTokensComponent,
} from './ChatReferences'

const meta = {
  title: 'Apps/Copilot/ChatReferences',
  component: ChatMessageReferencesList,
  parameters: {},
  argTypes: {},
} satisfies Meta<typeof ChatMessageReferencesList>

export default meta

const defaultArgs: ChatMessageReferencesListProps = {
  references: [getRepositoryReferenceMock(), getSnippetReferenceMock(), getSymbolReferenceMock()],
}

export const Example = {
  args: {
    ...defaultArgs,
  },
  render: (args: ChatMessageReferencesListProps) => {
    return (
      <CopilotChatProvider {...getCopilotChatProviderProps()}>
        <ChatMessageReferencesList {...args} />
      </CopilotChatProvider>
    )
  },
}

export const ChatMessageReferenceTokens = {
  args: {
    size: 'small',
    className: 'mb-2',
    references: [...getReferencesMock(), getIssueReferenceMock(), getPullRequestReferenceMock()],
  },
  render: (args: ChatMessageReferenceTokensProps) => {
    return (
      <CopilotChatProvider {...getCopilotChatProviderProps()}>
        <ChatMessageReferenceTokensComponent {...args} />
      </CopilotChatProvider>
    )
  },
}

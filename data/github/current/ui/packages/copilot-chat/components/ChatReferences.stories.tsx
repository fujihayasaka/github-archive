import type {Meta} from '@storybook/react'

import {
  getCopilotChatProviderProps,
  getRepositoryReferenceMock,
  getSnippetReferenceMock,
  getSymbolReferenceMock,
} from '../test-utils/mock-data'
import {CopilotChatProvider} from '../utils/CopilotChatContext'
import type {ChatMessageReferencesListProps} from './ChatReferences'
import {ChatMessageReferencesList} from './ChatReferences'

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

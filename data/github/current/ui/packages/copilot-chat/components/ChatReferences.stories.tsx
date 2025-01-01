import type {Meta} from '@storybook/react'

import {
  getCopilotChatProviderProps,
  getRepositoryReferenceMock,
  getSnippetReferenceMock,
  getSymbolReferenceMock,
} from '../test-utils/mock-data'
import {CopilotChatProvider} from '../utils/CopilotChatContext'
import type {ChatReferencesProps} from './ChatReferences'
import {ChatReferences} from './ChatReferences'

const meta = {
  title: 'Apps/Copilot/ChatReferences',
  component: ChatReferences,
  parameters: {},
  argTypes: {},
} satisfies Meta<typeof ChatReferences>

export default meta

const defaultArgs: ChatReferencesProps = {
  references: [getRepositoryReferenceMock(), getSnippetReferenceMock(), getSymbolReferenceMock()],
}

export const Example = {
  args: {
    ...defaultArgs,
  },
  render: (args: ChatReferencesProps) => {
    return (
      <CopilotChatProvider {...getCopilotChatProviderProps()}>
        <ChatReferences {...args} />
      </CopilotChatProvider>
    )
  },
}

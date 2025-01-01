import {Wrapper} from '@github-ui/react-core/test-utils'
import {relayEnvironmentWithMissingFieldHandlerForNode} from '@github-ui/relay-environment'
import type {Meta} from '@storybook/react'
import {RelayEnvironmentProvider} from 'react-relay'

import {getCopilotChatProviderProps} from '../test-utils/mock-data'
import {CopilotChatProvider, type CopilotChatProviderProps} from '../utils/CopilotChatContext'
import {RepoSelectPanel, type RepoSelectPanelProps} from './RepoSelectPanel'

const meta = {
  title: 'Apps/Copilot/RepoSelectPanel',
  component: RepoSelectPanel,
  parameters: {},
  argTypes: {},
} satisfies Meta<typeof RepoSelectPanel>

export default meta

const defaultArgs: RepoSelectPanelProps = {
  open: true,
  onOpenChange: () => {},
  submitReturnFocusRef: {current: null},
  cancelReturnFocusRef: {current: null},
  selectedRepoIds: new Set([]),
  onSelectRepo: async () => {
    return Promise.resolve()
  },
  selectionVariant: 'instant',
  description: 'Description',
}

interface ContainerProps {
  children: React.ReactNode
  providerProps?: Partial<CopilotChatProviderProps>
}

const environment = relayEnvironmentWithMissingFieldHandlerForNode()

const Container = ({children, providerProps}: ContainerProps) => (
  <RelayEnvironmentProvider environment={environment}>
    <CopilotChatProvider {...getCopilotChatProviderProps()} {...providerProps}>
      <Wrapper>
        <div>{children}</div>
      </Wrapper>
    </CopilotChatProvider>
  </RelayEnvironmentProvider>
)

export const Example = {
  parameters: {
    a11y: {
      test: 'todo',
    },
  },
  args: {
    ...defaultArgs,
  },
  render: (args: RepoSelectPanelProps) => {
    return (
      <Container>
        <RepoSelectPanel {...args} />
      </Container>
    )
  },
}

import {Wrapper} from '@github-ui/react-core/test-utils'
import type {Meta} from '@storybook/react'

import {getCopilotChatProviderProps} from '../test-utils/mock-data'
import {DialogType} from '../utils/copilot-chat-types'
import {CopilotChatProvider, type CopilotChatProviderProps} from '../utils/CopilotChatContext'
import {Header, type HeaderProps} from './Header'

const meta = {
  title: 'Apps/Copilot/Header',
  component: Header,
  parameters: {},
  argTypes: {},
} satisfies Meta<typeof Header>

export default meta

const defaultArgs: HeaderProps = {
  staffDialogRef: {current: null},
  showStaffDialog: DialogType.None,
  setShowStaffDialog: () => {},
}

interface ContainerProps {
  children: React.ReactNode
  providerProps?: Partial<CopilotChatProviderProps>
}

const Container = ({children, providerProps}: ContainerProps) => (
  <CopilotChatProvider {...getCopilotChatProviderProps()} {...providerProps}>
    <Wrapper>
      <div>{children}</div>
    </Wrapper>
  </CopilotChatProvider>
)

export const Example = {
  args: {
    ...defaultArgs,
  },
  render: (args: HeaderProps) => {
    return (
      <Container>
        <Header {...args} />
      </Container>
    )
  },
}

export const ImmersiveExample = {
  args: {
    ...defaultArgs,
  },
  render: (args: HeaderProps) => {
    return (
      <Container>
        <Header {...args} isImmersive />
      </Container>
    )
  },
}

export const ListExample = {
  args: {
    ...defaultArgs,
  },
  render: (args: HeaderProps) => {
    return (
      <Container providerProps={{currentView: 'list'}}>
        <Header {...args} />
      </Container>
    )
  },
}

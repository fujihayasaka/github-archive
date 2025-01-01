import {RepoIcon} from '@primer/octicons-react'
import {Box} from '@primer/react'
import type {Meta, StoryObj} from '@storybook/react'

import {getCopilotChatProviderProps, getRepositoryMock} from '../test-utils/mock-data'
import type {CopilotChatMode} from '../utils/copilot-chat-types'
import {CopilotChatProvider} from '../utils/CopilotChatContext'
import {TopicIndicatorFlash, type TopicIndicatorFlashProps} from './TopicIndicatorFlash'

const meta = {
  title: 'Apps/Copilot/TopicIndicatorFlash',
  component: TopicIndicatorFlash,
  parameters: {},
  argTypes: {},
} satisfies Meta<typeof TopicIndicatorFlash>

export default meta

const defaultIcon = <RepoIcon />
const repo = getRepositoryMock()

const defaultArgs: TopicIndicatorFlashProps = {
  icon: defaultIcon,
  topic: repo,
}

interface ContainerProps {
  children: React.ReactNode
  mode: CopilotChatMode
}

const Container = ({children, mode}: ContainerProps) => (
  <CopilotChatProvider {...getCopilotChatProviderProps()}>
    <Box sx={{margin: '150px', width: mode === 'immersive' ? '800px' : '400px'}}>{children}</Box>
  </CopilotChatProvider>
)

export const ImmersiveMode: StoryObj<TopicIndicatorFlashProps & {mode: string}> = {
  args: {
    ...defaultArgs,
  },
  render: args => (
    <Container mode="immersive">
      <TopicIndicatorFlash {...args} />
    </Container>
  ),
}

export const AssistiveMode: StoryObj<TopicIndicatorFlashProps & {mode: string}> = {
  args: {
    ...defaultArgs,
    mode: 'assistive',
  },
  render: args => (
    <Container mode="assistive">
      <TopicIndicatorFlash {...args} />
    </Container>
  ),
}

import {Wrapper} from '@github-ui/react-core/test-utils'
import {Box} from '@primer/react'
import type {Meta, StoryObj} from '@storybook/react'

import {getCopilotChatProviderProps} from '../test-utils/mock-data'
import {CopilotChatProvider} from '../utils/CopilotChatContext'
import {ChatImage, type ChatImageProps} from './ChatImage'

const meta = {
  title: 'Apps/Copilot/ChatImage',
  component: ChatImage,
  parameters: {},
  argTypes: {},
} satisfies Meta<typeof ChatImage>

export default meta

const defaultArgs: Partial<ChatImageProps> = {
  src: 'https://customer-stories-feed.github.com/customer_stories/american-airlines/AAhero.jpg',
  alt: 'An image of a plane',
}

const Container = (props: {children: React.ReactNode}) => (
  <CopilotChatProvider {...getCopilotChatProviderProps()}>
    <Wrapper>
      <Box sx={{maxWidth: '500px'}}>{props.children}</Box>
    </Wrapper>
  </CopilotChatProvider>
)

export const Default: StoryObj<ChatImageProps> = {
  args: {
    ...defaultArgs,
  },
  render: (args: ChatImageProps) => {
    return (
      <Container>
        <ChatImage {...args} />
      </Container>
    )
  },
}
export const WithOverlay: StoryObj<ChatImageProps> = {
  args: {
    ...defaultArgs,
    useOverlay: true,
  },
  render: (args: ChatImageProps) => {
    return (
      <Container>
        <ChatImage {...args} />
      </Container>
    )
  },
}

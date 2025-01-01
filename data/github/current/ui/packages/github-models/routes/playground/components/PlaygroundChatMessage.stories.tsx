import type {Meta, StoryObj} from '@storybook/react'
import type {UserHookPayload} from '@github-ui/use-user'
import {Wrapper, storyWrapper} from '@github-ui/react-core/test-utils'
import {fn} from '@storybook/test'
import {PlaygroundChatMessage, type PlaygroundChatMessageProps} from './PlaygroundChatMessage'
import {mockModelState, mockStoredMessage} from './__tests__/mocks'
import type {ImageInputs} from '../../../types'
import {rateLimitedMessage} from './PlaygroundError'
import {mockShowModelPayload} from '../../show/components/__tests__/mocks'
import {mockModel} from '../__tests__/mocks'
import {parametersConfig} from '../../../utils/story-utils'

const model = mockModel
const modelState = mockModelState({catalogData: model})

const meta: Meta<PlaygroundChatMessageProps> = {
  title: 'Apps/GitHub Models/PlaygroundChatMessage',
  component: PlaygroundChatMessage,
  args: {
    model: modelState,
    isLoading: false,
    isError: false,
    index: 0,
    handleRegenerate: fn(),
    lastIndex: true,
    handleClearHistory: fn(),
  },
  argTypes: {
    model: {control: 'object'},
    isLoading: {control: 'boolean'},
    isError: {control: 'boolean'},
    index: {control: 'number'},
    handleRegenerate: {control: false},
    lastIndex: {control: 'boolean'},
    handleClearHistory: {control: false},
    message: {control: 'object'},
  },
  parameters: parametersConfig,
}

export default meta

type Story = StoryObj<PlaygroundChatMessageProps>

export const UserMessage: Story = {
  render: args => <PlaygroundChatMessage {...args} />,
  args: {
    message: Object.assign({}, mockStoredMessage, {role: 'user'}),
  },
  decorators: [
    Story => {
      const currentUser: Partial<UserHookPayload['current_user']> = {
        name: 'Monalisa Octocat',
        avatarUrl: 'https://github.com/octocat.png',
        login: 'octocat',
      }
      return (
        <Wrapper appPayload={{current_user: currentUser}}>
          <Story />
        </Wrapper>
      )
    },
  ],
}

export const AssistantMessage: Story = {
  render: args => <PlaygroundChatMessage {...args} />,
  args: {
    message: Object.assign({}, mockStoredMessage, {role: 'assistant'}),
  },
  decorators: [
    Story => (
      <Wrapper routePayload={mockShowModelPayload({model})}>
        <Story />
      </Wrapper>
    ),
  ],
}

export const RateLimitError: Story = {
  render: args => <PlaygroundChatMessage {...args} />,
  args: {
    isError: true,
    message: Object.assign({}, mockStoredMessage, {role: 'error', message: rateLimitedMessage}),
  },
  decorators: [
    storyWrapper({
      routePayload: mockShowModelPayload(),
    }),
  ],
}

export const GenericError: Story = {
  render: args => <PlaygroundChatMessage {...args} />,
  args: {
    isError: true,
    message: Object.assign({}, mockStoredMessage, {role: 'error', message: "It's all gone wrong!"}),
  },
  decorators: [
    storyWrapper({
      routePayload: mockShowModelPayload(),
    }),
  ],
}

const imageMessage: ImageInputs = {type: 'image_url', image_url: {url: 'https://github.com/octocat.png'}}

export const ImageAttachments: Story = {
  render: args => <PlaygroundChatMessage {...args} />,
  args: {
    message: Object.assign({}, mockStoredMessage, {message: [imageMessage]}),
  },
  decorators: [
    storyWrapper({
      routePayload: mockShowModelPayload(),
    }),
  ],
}

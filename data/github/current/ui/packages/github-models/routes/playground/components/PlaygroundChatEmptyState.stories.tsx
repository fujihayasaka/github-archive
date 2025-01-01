import type {Meta, StoryObj} from '@storybook/react'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {fn} from '@storybook/test'
import {ModelUrlHelper} from '../../../utils/model-url-helper'
import {PlaygroundStateProvider} from '../../../contexts/PlaygroundStateContext'
import PlaygroundChatEmptyState from './PlaygroundChatEmptyState'
import {mockModelState, mockPlaygroundState} from './__tests__/mocks'
import {parametersConfig} from '../../../utils/story-utils'

const modelState = mockModelState()

const meta: Meta<typeof PlaygroundChatEmptyState> = {
  title: 'Apps/GitHub Models/PlaygroundChatEmptyState',
  component: PlaygroundChatEmptyState,
  args: {
    model: modelState,
    submitMessage: fn(),
  },
  argTypes: {
    model: {control: 'object'},
    submitMessage: {control: false},
  },
  parameters: parametersConfig,
}

export default meta

type Story = StoryObj<typeof PlaygroundChatEmptyState>

export const Example: Story = {
  render: args => <PlaygroundChatEmptyState {...args} />,
  decorators: [
    Story => (
      <Wrapper pathname={ModelUrlHelper.playgroundUrl(modelState.catalogData)}>
        <PlaygroundStateProvider state={mockPlaygroundState({models: [modelState]})}>
          <Story />
        </PlaygroundStateProvider>
      </Wrapper>
    ),
  ],
}

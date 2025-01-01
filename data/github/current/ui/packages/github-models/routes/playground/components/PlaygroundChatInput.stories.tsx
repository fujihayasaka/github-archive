import type {Meta, StoryObj} from '@storybook/react'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {fn} from '@storybook/test'
import {ModelUrlHelper} from '../../../utils/model-url-helper'
import {Panel, type PlaygroundManager, PlaygroundManagerContext} from '../../../utils/playground-manager'
import {PlaygroundStateProvider} from '../../../contexts/PlaygroundStateContext'
import {AttachmentsProvider} from './attachments/AttachmentsProvider'
import {mockModelState, mockPlaygroundState} from './__tests__/mocks'
import {PlaygroundChatInput} from './PlaygroundChatInput'
import {parametersConfig} from '../../../utils/story-utils'

type StoryArgs = typeof PlaygroundChatInput

const modelState = mockModelState()

const meta: Meta<StoryArgs> = {
  title: 'Apps/GitHub Models/PlaygroundChatInput',
  component: PlaygroundChatInput,
  args: {
    model: modelState,
    position: Panel.Main,
    stopStreamingMessages: fn(),
    sendMessage: fn(),
  },
  argTypes: {
    model: {control: 'object'},
    position: {control: {type: 'radio', options: [Panel.Main, Panel.Side]}},
    stopStreamingMessages: {control: false},
    sendMessage: {control: false},
  },
  parameters: parametersConfig,
}

export default meta

type Story = StoryObj<StoryArgs>

export const Example: Story = {
  render: args => <PlaygroundChatInput {...args} />,
  decorators: [
    Story => {
      const manager = {} as PlaygroundManager
      manager.setChatInput = fn()

      return (
        <Wrapper pathname={ModelUrlHelper.playgroundUrl(modelState.catalogData)}>
          <PlaygroundManagerContext.Provider value={manager}>
            <PlaygroundStateProvider state={mockPlaygroundState({models: [modelState]})}>
              <AttachmentsProvider>
                <Story />
              </AttachmentsProvider>
            </PlaygroundStateProvider>
          </PlaygroundManagerContext.Provider>
        </Wrapper>
      )
    },
  ],
}

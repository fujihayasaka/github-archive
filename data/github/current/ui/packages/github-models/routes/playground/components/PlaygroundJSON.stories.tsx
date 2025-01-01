import type {Meta, StoryObj} from '@storybook/react'
import {fn} from '@storybook/test'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {modelPlaygroundPath} from '@github-ui/paths'
import {PlaygroundJSON, type PlaygroundJSONProps} from './PlaygroundJSON'
import {PlaygroundManagerProvider} from '../../../contexts/PlaygroundManagerContext'
import {parametersConfig, panelPositionArgType} from '../../../utils/story-utils'
import {AttachmentsProvider} from '@github-ui/attachments'
import {Panel, type PlaygroundManager} from '../../../utils/playground-manager'
import {mockModelState} from './__tests__/mocks'

const modelState = mockModelState()

const meta = {
  title: 'Apps/GitHub Models/PlaygroundJSON',
  component: PlaygroundJSON,
  args: {
    setToolbarContent: fn(),
    setFullWidthToolbarContent: fn(),
    stopStreamingMessages: fn(),
    sendMessage: fn(),
    position: Panel.Main,
    model: modelState,
  },
  argTypes: {
    setToolbarContent: {control: false},
    setFullWidthToolbarContent: {control: false},
    stopStreamingMessages: {control: false},
    sendMessage: {control: false},
    position: panelPositionArgType,
    model: {control: 'object'},
  },
  parameters: parametersConfig,
} satisfies Meta<PlaygroundJSONProps>

export default meta

type Story = StoryObj<PlaygroundJSONProps>

export const Example: Story = {
  render: args => <PlaygroundJSON {...args} />,
  decorators: [
    Story => (
      <Wrapper pathname={modelPlaygroundPath(modelState.catalogData)}>
        <Story />
      </Wrapper>
    ),
    Story => {
      const manager = {} as PlaygroundManager
      manager.setMessages = fn()

      return (
        <PlaygroundManagerProvider manager={manager}>
          <AttachmentsProvider>
            <Story />
          </AttachmentsProvider>
        </PlaygroundManagerProvider>
      )
    },
  ],
}

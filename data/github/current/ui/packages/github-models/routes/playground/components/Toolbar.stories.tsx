import type {Meta, StoryObj} from '@storybook/react'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {fn} from '@storybook/test'
import {modelPlaygroundPath} from '@github-ui/paths'
import {Toolbar} from './Toolbar'
import {mockModelState} from './__tests__/mocks'
import {mockModel} from '../__tests__/mocks'
import {Panel, type PlaygroundManager} from '../../../utils/playground-manager'
import {PlaygroundContentOption} from './types'
import {panelPositionArgType, parametersConfig} from '../../../utils/story-utils'
import {PlaygroundManagerProvider} from '../../../contexts/PlaygroundManagerContext'

type StoryArgs = typeof Toolbar

const meta: Meta<StoryArgs> = {
  title: 'Apps/GitHub Models/Toolbar',
  component: Toolbar,
  args: {
    children: 'This is the content inside the toolbar, for option=JSON.',
    modelState: mockModelState({catalogData: mockModel}),
    position: Panel.Main,
    onComparisonMode: false,
    option: PlaygroundContentOption.CHAT,
  },
  argTypes: {
    children: {control: 'text'},
    modelState: {control: {type: 'object'}},
    position: panelPositionArgType,
    onComparisonMode: {control: 'boolean'},
    option: {
      control: 'select',
      description: `Playground content option: ${PlaygroundContentOption.CHAT}=CHAT, ${PlaygroundContentOption.CODE}=CODE, ${PlaygroundContentOption.JSON}=JSON`,
      options: [PlaygroundContentOption.CHAT, PlaygroundContentOption.CODE, PlaygroundContentOption.JSON],
    },
  },
  parameters: parametersConfig,
}

export default meta

type Story = StoryObj<StoryArgs>

export const Example: Story = {
  render: args => <Toolbar {...args} />,
  decorators: [
    Story => {
      const manager = {} as PlaygroundManager
      manager.resetHistory = fn()
      manager.setMessages = fn()
      manager.setSyncInputs = fn()

      return (
        <Wrapper pathname={modelPlaygroundPath(mockModel)}>
          <PlaygroundManagerProvider manager={manager}>
            <Story />
          </PlaygroundManagerProvider>
        </Wrapper>
      )
    },
  ],
}

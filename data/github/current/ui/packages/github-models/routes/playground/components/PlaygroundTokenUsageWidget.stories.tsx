import type {Meta, StoryObj} from '@storybook/react'
import {modelPlaygroundPath} from '@github-ui/paths'
import {mockModelState, mockPlaygroundState} from './__tests__/mocks'
import {panelPositionArgType, parametersConfig} from '../../../utils/story-utils'
import {PlaygroundTokenUsageWidget} from './PlaygroundTokenUsageWidget'
import type {PlaygroundManager} from '../../../utils/playground-manager'
import {Panel} from '../../../utils/playground-manager'
import {PlaygroundManagerProvider} from '../../../contexts/PlaygroundManagerContext'
import {fn} from '@storybook/test'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {PlaygroundStateProvider} from '../../../contexts/PlaygroundStateContext'
import {AttachmentsProvider} from '@github-ui/attachments'

const modelStateOne = mockModelState({isLoading: false})
const modelStateTwo = mockModelState()

type StoryArgs = typeof PlaygroundTokenUsageWidget

const meta: Meta<StoryArgs> = {
  title: 'Apps/GitHub Models/PlaygroundTokenUsageWidget',
  component: PlaygroundTokenUsageWidget,
  args: {
    modelState: modelStateOne,
    position: Panel.Main,
  },
  argTypes: {
    modelState: {control: 'object'},
    position: panelPositionArgType,
  },
  parameters: parametersConfig,
}

export default meta

type Story = StoryObj<StoryArgs>

export const OneModel: Story = {
  render: args => <PlaygroundTokenUsageWidget {...args} />,
  decorators: [
    Story => {
      const manager = {} as PlaygroundManager
      manager.setChatInput = fn()

      return (
        <Wrapper pathname={modelPlaygroundPath(modelStateOne.catalogData)}>
          <PlaygroundManagerProvider manager={manager}>
            <PlaygroundStateProvider state={mockPlaygroundState({models: [modelStateOne]})}>
              <AttachmentsProvider>
                <Story />
              </AttachmentsProvider>
            </PlaygroundStateProvider>
          </PlaygroundManagerProvider>
        </Wrapper>
      )
    },
  ],
}

export const TwoModels: Story = {
  render: args => <PlaygroundTokenUsageWidget {...args} />,
  decorators: [
    Story => {
      const manager = {} as PlaygroundManager
      manager.setChatInput = fn()

      return (
        <Wrapper pathname={modelPlaygroundPath(modelStateOne.catalogData)}>
          <PlaygroundManagerProvider manager={manager}>
            <PlaygroundStateProvider state={mockPlaygroundState({models: [modelStateOne, modelStateTwo]})}>
              <AttachmentsProvider>
                <Story />
              </AttachmentsProvider>
            </PlaygroundStateProvider>
          </PlaygroundManagerProvider>
        </Wrapper>
      )
    },
  ],
}

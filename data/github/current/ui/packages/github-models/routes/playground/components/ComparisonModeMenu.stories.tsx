import type {Meta, StoryObj} from '@storybook/react'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {fn} from '@storybook/test'
import {ModelUrlHelper} from '../../../utils/model-url-helper'
import {ComparisonModeMenu} from './ComparisonModeMenu'
import {Panel, PlaygroundManagerContext, type PlaygroundManager} from '../../../utils/playground-manager'
import {PlaygroundStateProvider} from '../../../contexts/PlaygroundStateContext'
import {mockModelState, mockPlaygroundState} from './__tests__/mocks'
import {panelPositionArgType, parametersConfig} from '../../../utils/story-utils'

const modelState = mockModelState()

type StoryArgs = typeof ComparisonModeMenu

const meta: Meta<StoryArgs> = {
  title: 'Apps/GitHub Models/ComparisonModeMenu',
  component: ComparisonModeMenu,
  args: {
    modelState,
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

export const Example: Story = {
  render: args => <ComparisonModeMenu {...args} />,
  decorators: [
    Story => {
      const manager = {} as PlaygroundManager
      manager.setModelState = fn()
      manager.setSyncInputs = fn()
      manager.setParameters = fn()
      manager.resetParamsAndSystemPrompt = fn()

      return (
        <Wrapper pathname={ModelUrlHelper.playgroundUrl(modelState.catalogData)}>
          <PlaygroundManagerContext.Provider value={manager}>
            <PlaygroundStateProvider state={mockPlaygroundState({models: [modelState]})}>
              <Story />
            </PlaygroundStateProvider>
          </PlaygroundManagerContext.Provider>
        </Wrapper>
      )
    },
  ],
}

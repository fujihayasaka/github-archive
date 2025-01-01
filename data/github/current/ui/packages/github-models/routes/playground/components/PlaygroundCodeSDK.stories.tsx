import type {Meta, StoryObj} from '@storybook/react'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {fn} from '@storybook/test'
import {mockGettingStarted, mockModel} from '../../playground/__tests__/mocks'
import {ModelUrlHelper} from '../../../utils/model-url-helper'
import {PlaygroundManagerContext, type PlaygroundManager} from '../../../utils/playground-manager'
import {PlaygroundStateProvider} from '../../../contexts/PlaygroundStateContext'
import {PlaygroundCodeSDK} from './PlaygroundCodeSDK'
import {mockPlaygroundState} from './__tests__/mocks'
import {parametersConfig} from '../../../utils/story-utils'

const selectedLanguage = 'intercal'
const gettingStarted = Object.assign({}, mockGettingStarted, {
  [selectedLanguage]: {name: 'INTERCAL', sdks: {'some-sdk': {name: 'Some SDK'}, 'other-sdk': {name: 'Other SDK'}}},
})

type StoryArgs = typeof PlaygroundCodeSDK

const meta: Meta<StoryArgs> = {
  title: 'Apps/GitHub Models/PlaygroundCodeSDK',
  component: PlaygroundCodeSDK,
  args: {
    gettingStarted,
  },
  argTypes: {
    gettingStarted: {control: 'object'},
  },
  parameters: parametersConfig,
}

export default meta

type Story = StoryObj<StoryArgs>

export const Example: Story = {
  render: args => <PlaygroundCodeSDK {...args} />,
  decorators: [
    Story => {
      const manager = {} as PlaygroundManager
      manager.setSelectedSDK = fn()

      return (
        <Wrapper pathname={ModelUrlHelper.playgroundUrl(mockModel)}>
          <PlaygroundManagerContext.Provider value={manager}>
            <PlaygroundStateProvider state={mockPlaygroundState({selectedLanguage})}>
              <Story />
            </PlaygroundStateProvider>
          </PlaygroundManagerContext.Provider>
        </Wrapper>
      )
    },
  ],
}

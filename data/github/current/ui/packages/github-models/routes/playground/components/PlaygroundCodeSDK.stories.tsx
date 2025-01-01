import type {Meta, StoryObj} from '@storybook/react'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {modelPlaygroundPath} from '@github-ui/paths'
import {mockGettingStarted, mockModel} from '../../playground/__tests__/mocks'
import {PlaygroundStateProvider} from '../../../contexts/PlaygroundStateContext'
import {PlaygroundCodeSDK} from './PlaygroundCodeSDK'
import {mockPlaygroundState} from './__tests__/mocks'
import {parametersConfig} from '../../../utils/story-utils'

const selectedLanguage = 'intercal'
const gettingStarted = Object.assign({}, mockGettingStarted, {
  [selectedLanguage]: {name: 'INTERCAL', sdks: {'some-sdk': {name: 'Some SDK'}, 'other-sdk': {name: 'Other SDK'}}},
})
const uiState = {
  sidebarTab: 0,
  showSidebar: true,
  preferredLanguage: selectedLanguage,
  preferredSdk: 'some-sdk',
} as const

type StoryArgs = typeof PlaygroundCodeSDK

const meta: Meta<StoryArgs> = {
  title: 'Apps/GitHub Models/PlaygroundCodeSDK',
  component: PlaygroundCodeSDK,
  args: {
    gettingStarted,
    uiState,
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
      return (
        <Wrapper pathname={modelPlaygroundPath(mockModel)}>
          <PlaygroundStateProvider state={mockPlaygroundState()}>
            <Story />
          </PlaygroundStateProvider>
        </Wrapper>
      )
    },
  ],
}

import type {Meta, StoryObj} from '@storybook/react'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {fn} from '@storybook/test'
import {modelPlaygroundPath} from '@github-ui/paths'
import {mockModel} from '../../playground/__tests__/mocks'
import type {PlaygroundManager} from '../../../utils/playground-manager'
import {PlaygroundManagerProvider} from '../../../contexts/PlaygroundManagerContext'
import {PlaygroundError, type PlaygroundErrorProps} from './PlaygroundError'
import {parametersConfig} from '../../../utils/story-utils'

const meta: Meta<PlaygroundErrorProps> = {
  title: 'Apps/GitHub Models/PlaygroundError',
  component: PlaygroundError,
  args: {
    message: "It's all gone wrong",
    showResetButton: true,
  },
  argTypes: {
    message: {control: 'text'},
    showResetButton: {control: {type: 'boolean'}},
  },
  parameters: parametersConfig,
}

export default meta

type Story = StoryObj<PlaygroundErrorProps>

export const Example: Story = {
  render: args => <PlaygroundError {...args} />,
  decorators: [
    Story => {
      const manager = {} as PlaygroundManager
      manager.resetHistory = fn()
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

import type {Meta, StoryFn, StoryObj} from '@storybook/react'
import {parametersConfig} from '../../../../utils/story-utils'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import GettingStartedDialog, {type GettingStartedDialogProps} from './GettingStartedDialog'
import {mockGettingStarted} from '../../__tests__/mocks'
import {CurrentRepositoryProvider} from '@github-ui/current-repository'
import {createRepository} from '@github-ui/current-repository/test-helpers'

type StoryArgs = GettingStartedDialogProps

const currentRepositoryDecorator = (Story: StoryFn) => (
  <CurrentRepositoryProvider repository={createRepository()}>
    <Story />
  </CurrentRepositoryProvider>
)

const meta: Meta<StoryArgs> = {
  title: 'Apps/GitHub Models/GettingStartedDialog',
  component: GettingStartedDialog,
  decorators: [currentRepositoryDecorator, storyWrapper({appPayload: {helpUrl: ''}})],
  args: {
    onClose: () => {},
    openInCodespaceUrl: '/some/url',
    showCodespacesSuggestion: true,
    gettingStarted: {
      ...mockGettingStarted,
    },
    modelName: 'Model-4o',
  },
  argTypes: {},
  parameters: parametersConfig,
}

export default meta

type Story = StoryObj<StoryArgs>

export const Example: Story = {
  parameters: {},
  render: args => <GettingStartedDialog {...args} />,
}

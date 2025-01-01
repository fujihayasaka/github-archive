import type {Meta, StoryObj} from '@storybook/react'
import {fn} from '@storybook/test'
import {modelPlaygroundPath} from '@github-ui/paths'
import {SharePresetDialog, type SharePresetDialogProps} from './SharePresetDialog'
import {parametersConfig} from '../../../../utils/story-utils'
import {mockModel, mockPreset} from '../../__tests__/mocks'

const meta: Meta<SharePresetDialogProps> = {
  title: 'Apps/GitHub Models/SharePresetDialog',
  component: SharePresetDialog,
  args: {
    onClose: fn(),
    playgroundUrl: modelPlaygroundPath(mockModel),
    urlIdentifier: mockPreset.urlIdentifier,
  },
  argTypes: {
    onClose: {control: false},
    playgroundUrl: {control: 'text'},
    urlIdentifier: {control: 'text'},
  },
  parameters: parametersConfig,
}

export default meta

type Story = StoryObj<SharePresetDialogProps>

export const Example: Story = {
  render: args => <SharePresetDialog {...args} />,
}

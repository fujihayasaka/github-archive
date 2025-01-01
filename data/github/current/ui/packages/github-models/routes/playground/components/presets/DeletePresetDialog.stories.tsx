import type {Meta, StoryObj} from '@storybook/react'
import {fn} from '@storybook/test'
import {DeletePresetDialog} from './DeletePresetDialog'
import {parametersConfig} from '../../../../utils/story-utils'
import {mockPreset} from '../../__tests__/mocks'

type StoryArgs = typeof DeletePresetDialog

const meta: Meta<StoryArgs> = {
  title: 'Apps/GitHub Models/DeletePresetDialog',
  component: DeletePresetDialog,
  args: {
    onClose: fn(),
    onSuccess: fn(),
    selectedPreset: mockPreset,
  },
  argTypes: {
    onClose: {control: false},
    onSuccess: {control: false},
    selectedPreset: {control: 'object'},
  },
  parameters: parametersConfig,
}

export default meta

type Story = StoryObj<StoryArgs>

export const Default: Story = {
  render: args => <DeletePresetDialog {...args} />,
}

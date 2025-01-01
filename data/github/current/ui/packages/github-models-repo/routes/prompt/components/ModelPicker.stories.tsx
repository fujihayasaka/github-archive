import type {Meta, StoryObj} from '@storybook/react'
import {fn} from '@storybook/test'
import {ModelsProvider} from '../contexts/ModelsContext'
import {mockModels} from '../../../test-utils/mock-data'
import ModelPicker from './ModelPicker'

const meta = {
  title: 'Apps/GitHub Models repository/ModelPicker',
  component: ModelPicker,
  args: {onSelect: fn()},
  decorators: [
    Story => (
      <ModelsProvider models={mockModels}>
        <Story />
      </ModelsProvider>
    ),
  ],
} satisfies Meta<typeof ModelPicker>

export default meta

type Story = StoryObj<typeof ModelPicker>

export const Example = {} satisfies Story

import type {Meta, StoryObj} from '@storybook/react'
import {fn} from '@storybook/test'

import {mockCustomKeys, mockCustomModels} from '../test-utils/mocks'
import {AvailableModels} from './AvailableModels'

export default {
  title: 'Apps/Models BYOK settings/Components/AvailableModels',
  component: AvailableModels,
  args: {
    customKeys: mockCustomKeys(),
    customModels: mockCustomModels(),
    updateModel: fn(),
  },
} satisfies Meta<typeof AvailableModels>

type Story = StoryObj<typeof AvailableModels>

export const Default: Story = {}

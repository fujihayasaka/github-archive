import type {Meta, StoryObj} from '@storybook/react'
import {fn} from '@storybook/test'

import {mockCustomKey, mockCustomModel} from '../test-utils/mocks'
import {AvailableModel} from './AvailableModel'

const customKey = mockCustomKey()

export default {
  title: 'Apps/Models BYOK settings/Components/AvailableModel',
  component: AvailableModel,
  args: {
    customKey,
    model: mockCustomModel({customKeyId: customKey.id, enabled: {copilot: true, models: false}}),
    updateModel: fn(),
  },
} satisfies Meta<typeof AvailableModel>

type Story = StoryObj<typeof AvailableModel>

export const Default: Story = {}

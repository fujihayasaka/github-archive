import type {Meta, StoryObj} from '@storybook/react'

import {mockCustomKeys} from '../test-utils/mocks'
import {ApiKeys} from './ApiKeys'

export default {
  title: 'Apps/Models BYOK settings/Components/ApiKeys',
  component: ApiKeys,
  args: {
    customKeys: mockCustomKeys(),
  },
} satisfies Meta<typeof ApiKeys>

type Story = StoryObj<typeof ApiKeys>

export const Default: Story = {}

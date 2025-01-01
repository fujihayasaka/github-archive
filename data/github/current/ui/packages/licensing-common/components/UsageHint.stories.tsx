import type {Meta, StoryObj} from '@storybook/react'
import {UsageHint} from './UsageHint'

const meta = {
  title: 'Apps/Licensing/Common/UsageHint',
  component: UsageHint,
  args: {
    title: 'Consumed licenses',
  },
} satisfies Meta<typeof UsageHint>

export default meta

type Story = StoryObj<typeof UsageHint>

export const Default: Story = {}

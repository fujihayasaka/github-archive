import type {Meta, StoryObj} from '@storybook/react'
import {UsageSummary} from './UsageSummary'

const meta = {
  title: 'Apps/Licensing/Common/UsageSummary',
  component: UsageSummary,
  args: {
    title: 'Consumed licenses',
  },
} satisfies Meta<typeof UsageSummary>

export default meta

type Story = StoryObj<typeof UsageSummary>

export const Default: Story = {}

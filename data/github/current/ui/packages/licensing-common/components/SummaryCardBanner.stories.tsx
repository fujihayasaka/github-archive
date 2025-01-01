import type {Meta, StoryObj} from '@storybook/react'
import {SummaryCardBanner} from './SummaryCardBanner'

const meta = {
  title: 'Apps/Licensing/Common/SummaryCardBanner',
  component: SummaryCardBanner,
  args: {
    title: 'Banner title',
    description: 'Banner description',
  },
} satisfies Meta<typeof SummaryCardBanner>

export default meta

type Story = StoryObj<typeof SummaryCardBanner>

export const Default: Story = {}

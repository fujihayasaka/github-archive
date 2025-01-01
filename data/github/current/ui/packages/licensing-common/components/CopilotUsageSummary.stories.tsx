import type {Meta, StoryObj} from '@storybook/react'
import {CopilotUsageSummary} from './CopilotUsageSummary'
import {getSkus} from '../test-utils/mock-data'

const meta = {
  title: 'Apps/Licensing/Common/CopilotUsageSummary',
  component: CopilotUsageSummary,
  args: {
    skus: getSkus(),
    headingLevel: 'h3',
  },
} satisfies Meta<typeof CopilotUsageSummary>

export default meta

type Story = StoryObj<typeof CopilotUsageSummary>

export const Default: Story = {}

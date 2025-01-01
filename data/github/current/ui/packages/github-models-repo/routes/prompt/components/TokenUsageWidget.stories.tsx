import type {Meta, StoryObj} from '@storybook/react'
import {TokenUsageWidget} from './TokenUsageWidget'
import {mockModel, mockTokenUsage} from '../../../test-utils/mock-data'

const meta = {
  title: 'Apps/GitHub Models repository/TokenUsageWidget',
  component: TokenUsageWidget,
  args: {
    model: mockModel(),
    tokenUsage: mockTokenUsage({lastMessageOutputTokens: 1200, totalOutputTokens: 123456}),
  },
} satisfies Meta<typeof TokenUsageWidget>

export default meta

type Story = StoryObj<typeof TokenUsageWidget>

export const Example = {} satisfies Story

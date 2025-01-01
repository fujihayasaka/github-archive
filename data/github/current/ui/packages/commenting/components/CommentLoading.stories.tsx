import type {Meta, StoryObj} from '@storybook/react'

import {CommentLoading} from './CommentLoading'

const meta = {
  title: 'Commenting/CommentLoading',
  component: CommentLoading,
  parameters: {
    controls: {
      expanded: true,
    },
  },
  tags: ['autodocs'],
} satisfies Meta<typeof CommentLoading>

export default meta
type Story = StoryObj<typeof meta>

/**
 * Default story showing the loading skeleton for a comment
 */
export const Default: Story = {
  args: {
    inHighlightedTimeline: false,
  },
}

/**
 * Story showing the loading skeleton in a highlighted timeline,
 * where the avatar is hidden on smaller screens
 */
export const InHighlightedTimeline: Story = {
  args: {
    inHighlightedTimeline: true,
  },
  parameters: {
    viewport: {
      defaultViewport: 'mobile1',
    },
    docs: {
      description: {
        story: 'Demonstrates the loading skeleton in a highlighted timeline where avatar is responsive',
      },
    },
  },
}

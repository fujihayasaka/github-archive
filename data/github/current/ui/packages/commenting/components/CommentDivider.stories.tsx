import type {Meta, StoryObj} from '@storybook/react'

import {CommentDivider} from './CommentDivider'

const meta = {
  title: 'Commenting/CommentDivider',
  component: CommentDivider,
  parameters: {
    controls: {expanded: true},
    layout: 'centered',
  },
  tags: ['autodocs'],
} satisfies Meta<typeof CommentDivider>

export default meta
type Story = StoryObj<typeof meta>

export const Default: Story = {
  args: {
    large: false,
    isLoading: false,
    isHovered: false,
  },
}

export const Large: Story = {
  args: {
    large: true,
    isLoading: false,
    isHovered: false,
  },
}

export const Loading: Story = {
  args: {
    large: false,
    isLoading: true,
    isHovered: false,
  },
}

export const Hovered: Story = {
  args: {
    large: false,
    isLoading: false,
    isHovered: true,
  },
}

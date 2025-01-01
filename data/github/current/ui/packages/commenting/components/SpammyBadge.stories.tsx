import type {Meta, StoryObj} from '@storybook/react'

import {SpammyBadge} from './SpammyBadge'

const meta: Meta<typeof SpammyBadge> = {
  title: 'Recipes/CommentBox/SpammyBadge',
  component: SpammyBadge,
}

type Story = StoryObj<typeof SpammyBadge>

export const Example: Story = {
  render: () => <SpammyBadge />,
}

export default meta

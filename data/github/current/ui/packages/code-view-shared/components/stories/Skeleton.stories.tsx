import type {Meta, StoryObj} from '@storybook/react'

import {SkeletonText} from '../Skeleton'

const meta = {
  title: 'Apps/Code View Shared/SkeletonText',
  component: SkeletonText,
  args: {width: 200},
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof SkeletonText>

export default meta

type Story = StoryObj<typeof SkeletonText>

export const Default: Story = {}

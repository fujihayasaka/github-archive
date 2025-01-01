import type {Meta, StoryObj} from '@storybook/react'
import {IssuesLoadingSkeleton} from './IssuesLoadingSkeleton'

const meta = {
  title: 'Utilities/IssuesLoadingSkeleton',
  component: IssuesLoadingSkeleton,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof IssuesLoadingSkeleton>

export default meta
type Story = StoryObj<typeof meta>

export const IssuesSkeletonExample: Story = {
  args: {
    width: '100px',
    height: 'sm',
    borderRadius: '4px',
  },
  render: ({width, height, borderRadius}) => (
    <IssuesLoadingSkeleton width={width} height={height} borderRadius={borderRadius} />
  ),
}

export const IssuesSkeletonRandomWidthExample: Story = {
  args: {
    width: 'random',
    height: 'md',
    borderRadius: '8px',
  },
  render: ({width, height, borderRadius}) => (
    <IssuesLoadingSkeleton width={width} height={height} borderRadius={borderRadius} />
  ),
}

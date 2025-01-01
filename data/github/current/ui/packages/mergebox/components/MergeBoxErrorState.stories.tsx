import type {Meta, StoryObj} from '@storybook/react'
import {MergeBoxErrorState} from './MergeBoxErrorState'

const meta: Meta<typeof MergeBoxErrorState> = {
  title: 'Pull Requests/Merge Box/MergeBoxErrorState',
  component: MergeBoxErrorState,
}

type Story = StoryObj<typeof MergeBoxErrorState>

export const Default: Story = {
  render: () => <MergeBoxErrorState />,
}

export default meta

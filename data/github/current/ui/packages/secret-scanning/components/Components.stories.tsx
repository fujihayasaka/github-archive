import type {Meta, StoryObj} from '@storybook/react'
import {Button} from './Components'

// This story is just to satisfy CI; not actually intended as documentation
const meta: Meta = {
  title: 'Secret Scanning / Components',
  component: Button,
  parameters: {
    layout: 'centered',
  },
  tags: ['autodocs'],
}
export default meta

type StoryButton = StoryObj<typeof Button>

/**
 * Inactive button onClick logic won't run
 */
export const InactiveButton: StoryButton = {
  args: {
    inactive: true,
    onClick: () => {
      alert("I won't be called")
    },
    children: 'Inactive Button',
  },
}

import type {StoryObj} from '@storybook/react'
import {Flash} from './Flash'

export default {
  title: 'Mkt/Swp/Flash',
  component: Flash,
}

type Story = StoryObj<typeof Flash>

export const Success: Story = {
  render: () => <Flash variant="success">This is a success message!</Flash>,
}

export const Error: Story = {
  render: () => <Flash variant="error">This is an error message!</Flash>,
}

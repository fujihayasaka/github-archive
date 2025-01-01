import type {Meta, StoryObj} from '@storybook/react'
import {expect, userEvent, within} from '@storybook/test'

import {InlineEdit} from './InlineEdit'

export default {
  title: 'Apps/Models BYOK settings/Components/InlineEdit',
  component: InlineEdit,
  args: {
    enabled: true,
    children: <p>Hello world</p>,
    defaultValue: 'hello world',
  },
} satisfies Meta<typeof InlineEdit>

type Story = StoryObj<typeof InlineEdit>

export const Default: Story = {}

export const Editing: Story = {
  async play({canvasElement}) {
    const canvas = within(canvasElement)

    await userEvent.click(canvas.getByRole('button', {name: 'Edit'}))

    await expect(canvas.getByLabelText('Edit value')).toBeInTheDocument()
  },
}

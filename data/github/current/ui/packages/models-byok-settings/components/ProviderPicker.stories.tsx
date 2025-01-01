import type {Meta, StoryObj} from '@storybook/react'
import {expect, userEvent, within} from '@storybook/test'

import {getProviders} from '../test-utils/mocks'
import {ProviderPicker} from './ProviderPicker'

const providers = getProviders()

export default {
  title: 'Apps/Models BYOK settings/Components/ProviderPicker',
  component: ProviderPicker,
  args: {
    providers,
  },
} satisfies Meta<typeof ProviderPicker>

type Story = StoryObj<typeof ProviderPicker>

export const Default: Story = {}

export const WithSelection: Story = {
  args: {
    selected: providers.at(1),
  },
}

export const Interactions: Story = {
  async play({canvasElement}) {
    const canvas = within(canvasElement)
    await userEvent.click(canvas.getByRole('button', {name: 'Select provider'}))
    await expect(canvas.getByRole('option', {name: 'OpenAI'})).toBeInTheDocument()
    const searchField = canvas.getByLabelText('Filter providers')
    await userEvent.type(searchField, 'Azure')
    await expect(canvas.queryByRole('option', {name: 'OpenAI'})).not.toBeInTheDocument()
  },
}

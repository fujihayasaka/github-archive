import type {Meta, StoryObj} from '@storybook/react'
import {expect, fn, userEvent, within} from '@storybook/test'

import {CurrentOrgProvider} from '../contexts/CurrentOrgContext'
import {customModelsIndexRouteHandlers, getMockPublicKey} from '../test-utils/mocks'
import {AddKeyDialog} from './AddKeyDialog'

export default {
  title: 'Apps/Models BYOK settings/Components/AddKeyDialog',
  component: AddKeyDialog,
  args: {
    onCancel: fn(),
    onSuccess: fn(),
    publicKey: getMockPublicKey(),
  },
  decorators: [
    Story => (
      <CurrentOrgProvider value="my-org">
        <Story />
      </CurrentOrgProvider>
    ),
  ],
  parameters: {
    msw: {
      handlers: customModelsIndexRouteHandlers,
    },
  },
} satisfies Meta<typeof AddKeyDialog>

type Story = StoryObj<typeof AddKeyDialog>

export const Default: Story = {}

export const AsOpenAI: Story = {
  async play({canvasElement}) {
    const canvas = within(canvasElement)
    await userEvent.click(canvas.getByRole('button', {name: 'Provider'}))
    await userEvent.click(canvas.getByRole('option', {name: 'OpenAI'}))
  },
}

export const AsAzure: Story = {
  async play({canvasElement}) {
    const canvas = within(canvasElement)
    await userEvent.click(canvas.getByRole('button', {name: 'Provider'}))
    await userEvent.click(canvas.getByRole('option', {name: 'Azure AI'}))

    await expect(canvas.getByLabelText('Deployment URL*')).toBeVisible()
    await expect(canvas.getByLabelText('Model ID*')).toBeVisible()
  },
}

import type {Meta, StoryContext, StoryFn, StoryObj} from '@storybook/react'
import {accessPolicyShow} from '../routes/access-policy-show-route'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import {OrganizationAccessPolicyProvider} from '../contexts/OrganizationAccessPolicyContext'
import {ModelsGlobalAccessToggle} from './ModelsGlobalAccessToggle'
import {mockAccessPolicyShowPayload, mockHandlers} from '../test-utils/mocks'
import {userEvent, within, expect, waitFor} from '@storybook/test'

const routePayload = mockAccessPolicyShowPayload()
const pathname = accessPolicyShow.generatePath({org: routePayload.orgDisplayLogin})

const meta = {
  title: 'Apps/GitHub Models org settings/ModelsGlobalAccessToggle',
  component: ModelsGlobalAccessToggle,
} satisfies Meta<typeof ModelsGlobalAccessToggle>

export default meta

type Decorator = (fn: StoryFn, c: StoryContext) => JSX.Element

const decorators: Decorator[] = [
  Story => (
    <OrganizationAccessPolicyProvider orgDisplayLogin={routePayload.orgDisplayLogin} policy={routePayload.policy}>
      <Story />
    </OrganizationAccessPolicyProvider>
  ),
  storyWrapper({pathname, routePayload}),
]

export const SuccessfulRequests: StoryObj = {
  decorators,
  parameters: {msw: {handlers: mockHandlers({pathname, type: 'success'})}},
  async play({canvasElement, step}) {
    const canvas = within(canvasElement)

    await step('Disable models', async () => {
      await userEvent.click(canvas.getByRole('button', {name: 'Models status: Enabled'}))
      await userEvent.click(canvas.getByRole('menuitemradio', {name: 'Disabled'}))
    })
  },
}

export const FailingRequests: StoryObj = {
  decorators,
  parameters: {msw: {handlers: mockHandlers({pathname, type: 'error'})}},
  async play({canvasElement, step}) {
    const canvas = within(canvasElement)

    await step('Disable models', async () => {
      await userEvent.click(canvas.getByRole('button', {name: 'Models status: Enabled'}))
      await userEvent.click(canvas.getByRole('menuitemradio', {name: 'Disabled'}))
    })

    await waitFor(async () => {
      expect(canvas.getByText(/a problem saving your policy/)).toBeInTheDocument()
    })
  },
}

export const InfiniteRequests: StoryObj = {
  decorators,
  parameters: {msw: {handlers: mockHandlers({pathname, type: 'loading'})}},
  async play({canvasElement, step}) {
    const canvas = within(canvasElement)

    await step('Disable models and verify loading state', async () => {
      await userEvent.click(canvas.getByRole('button', {name: 'Models status: Enabled'}))
      await userEvent.click(canvas.getByRole('menuitemradio', {name: 'Disabled'}))
    })

    await waitFor(() => {
      expect(canvas.getByRole('button', {name: /loading/i})).toBeInTheDocument()
    })
  },
}

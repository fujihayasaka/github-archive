import type {Meta, StoryContext, StoryFn, StoryObj} from '@storybook/react'
import {organizationSettingsModelsAccessPolicyPath} from '@github-ui/paths'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import {OrganizationAccessPolicyProvider} from '../contexts/OrganizationAccessPolicyContext'
import {ModelsGlobalAccessToggle} from './ModelsGlobalAccessToggle'
import {mockAccessPolicyShowPayload, mockHandlers} from '../test-utils/mocks'

const routePayload = mockAccessPolicyShowPayload()
const pathname = organizationSettingsModelsAccessPolicyPath({org: routePayload.orgDisplayLogin})

const meta = {
  title: 'Apps/GitHub Models org settings/ModelsGlobalAccessToggle',
  component: ModelsGlobalAccessToggle,
} satisfies Meta

export default meta

type Decorator = (fn: StoryFn, c: StoryContext) => JSX.Element

const decorators: Decorator[] = [
  Story => (
    <OrganizationAccessPolicyProvider>
      <Story />
    </OrganizationAccessPolicyProvider>
  ),
  storyWrapper({pathname, routePayload}),
]

export const SuccessfulRequests: StoryObj = {
  render: () => <ModelsGlobalAccessToggle />,
  decorators,
  parameters: {msw: {handlers: mockHandlers({pathname, type: 'success'})}},
}

export const FailingRequests: StoryObj = {
  render: () => <ModelsGlobalAccessToggle />,
  decorators,
  parameters: {msw: {handlers: mockHandlers({pathname, type: 'error'})}},
}

export const InfiniteRequests: StoryObj = {
  render: () => <ModelsGlobalAccessToggle />,
  decorators,
  parameters: {msw: {handlers: mockHandlers({pathname, type: 'loading'})}},
}

import type {Meta, StoryContext, StoryFn, StoryObj} from '@storybook/react'
import {repositorySettingsModelsAccessPolicyPath} from '@github-ui/paths'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import {ModelsAccessToggle} from './ModelsAccessToggle'
import {AccessPolicyProvider} from '../contexts/AccessPolicyContext'
import {mockAccessPolicyShowPayload, mockHandlers} from '../test-utils/mocks'

const routePayload = mockAccessPolicyShowPayload()
const pathname = repositorySettingsModelsAccessPolicyPath({
  owner: routePayload.ownerDisplayLogin,
  repo: routePayload.repositoryName,
})

const meta = {
  title: 'Apps/GitHub Models repo settings/ModelsAccessToggle',
  component: ModelsAccessToggle,
} satisfies Meta

export default meta

type Decorator = (fn: StoryFn, c: StoryContext) => JSX.Element

const decorators: Decorator[] = [
  Story => (
    <AccessPolicyProvider>
      <Story />
    </AccessPolicyProvider>
  ),
  storyWrapper({pathname, routePayload}),
]

export const SuccessfulRequests: StoryObj = {
  render: () => <ModelsAccessToggle />,
  decorators,
  parameters: {msw: {handlers: mockHandlers({pathname, type: 'success'})}},
}

export const FailingRequests: StoryObj = {
  render: () => <ModelsAccessToggle />,
  decorators,
  parameters: {msw: {handlers: mockHandlers({pathname, type: 'error'})}},
}

export const InfiniteRequests: StoryObj = {
  render: () => <ModelsAccessToggle />,
  decorators,
  parameters: {msw: {handlers: mockHandlers({pathname, type: 'loading'})}},
}

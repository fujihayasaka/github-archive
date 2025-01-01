import type {Meta, StoryObj} from '@storybook/react'
import {accessPolicyShow} from '../routes/access-policy-show-route'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import {OrganizationAccessPolicyProvider} from '../contexts/OrganizationAccessPolicyContext'
import {RuleListTypeToggle} from './RuleListTypeToggle'
import {mockAccessPolicyShowPayload, mockHandlers} from '../test-utils/mocks'

const routePayload = mockAccessPolicyShowPayload()
const pathname = accessPolicyShow.generatePath({org: routePayload.orgDisplayLogin})

const meta = {
  title: 'Apps/GitHub Models org settings/RuleListTypeToggle',
  component: RuleListTypeToggle,
} satisfies Meta<typeof RuleListTypeToggle>

export default meta

export const Example: StoryObj = {
  render: () => <RuleListTypeToggle />,
  decorators: [
    Story => (
      <OrganizationAccessPolicyProvider orgDisplayLogin={routePayload.orgDisplayLogin} policy={routePayload.policy}>
        <Story />
      </OrganizationAccessPolicyProvider>
    ),
    storyWrapper({pathname, routePayload}),
  ],
  parameters: {msw: {handlers: mockHandlers({pathname, type: 'success'})}},
}

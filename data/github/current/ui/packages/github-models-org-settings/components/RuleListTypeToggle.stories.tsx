import type {Meta, StoryObj} from '@storybook/react'
import {organizationSettingsModelsAccessPolicyPath} from '@github-ui/paths'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import {OrganizationAccessPolicyProvider} from '../contexts/OrganizationAccessPolicyContext'
import {RuleListTypeToggle} from './RuleListTypeToggle'
import {mockAccessPolicyShowPayload, mockHandlers} from '../test-utils/mocks'

const routePayload = mockAccessPolicyShowPayload()
const pathname = organizationSettingsModelsAccessPolicyPath({org: routePayload.orgDisplayLogin})

const meta = {
  title: 'Apps/GitHub Models org settings/RuleListTypeToggle',
  component: RuleListTypeToggle,
} satisfies Meta

export default meta

export const Example: StoryObj = {
  render: () => <RuleListTypeToggle />,
  decorators: [
    Story => (
      <OrganizationAccessPolicyProvider>
        <Story />
      </OrganizationAccessPolicyProvider>
    ),
    storyWrapper({pathname, routePayload}),
  ],
  parameters: {msw: {handlers: mockHandlers({pathname, type: 'success'})}},
}

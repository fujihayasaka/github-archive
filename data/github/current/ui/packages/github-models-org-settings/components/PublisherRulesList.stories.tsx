import type {Meta, StoryObj} from '@storybook/react'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import {organizationSettingsModelsAccessPolicyPath} from '@github-ui/paths'
import {OrganizationAccessPolicyProvider} from '../contexts/OrganizationAccessPolicyContext'
import {PublishersProvider} from '../contexts/PublishersContext'
import {mockAccessPolicyShowPayload, mockOrganizationAccessPolicy} from '../test-utils/mocks'
import {PublisherRulesList} from './PublisherRulesList'

const policy = mockOrganizationAccessPolicy()
const routePayload = mockAccessPolicyShowPayload({policy})
const pathname = organizationSettingsModelsAccessPolicyPath({org: routePayload.orgDisplayLogin})

const meta = {
  title: 'Apps/GitHub Models org settings/PublisherRulesList',
  component: PublisherRulesList,
} satisfies Meta

export default meta

export const Example: StoryObj = {
  render: () => <PublisherRulesList />,
  decorators: [
    Story => (
      <OrganizationAccessPolicyProvider>
        <PublishersProvider>
          <Story />
        </PublishersProvider>
      </OrganizationAccessPolicyProvider>
    ),
    storyWrapper({pathname, routePayload}),
  ],
}

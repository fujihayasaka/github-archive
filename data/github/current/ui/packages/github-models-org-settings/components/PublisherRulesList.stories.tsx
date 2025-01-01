import type {Meta, StoryObj} from '@storybook/react'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import {accessPolicyShow} from '../routes/access-policy-show-route'
import {OrganizationAccessPolicyProvider} from '../contexts/OrganizationAccessPolicyContext'
import {PublishersProvider} from '../contexts/PublishersContext'
import {mockAccessPolicyShowPayload, mockModel, mockOrganizationAccessPolicy, mockPublisher} from '../test-utils/mocks'
import {PublisherRulesList} from './PublisherRulesList'

const policy = mockOrganizationAccessPolicy()
const routePayload = mockAccessPolicyShowPayload({policy})
const pathname = accessPolicyShow.generatePath({org: routePayload.orgDisplayLogin})

const models = [mockModel()]
const publishers = [mockPublisher({id: 1, name: 'Foo'}), mockPublisher({id: 2, name: 'Bar'})]

const meta = {
  title: 'Apps/GitHub Models org settings/PublisherRulesList',
  component: PublisherRulesList,
  args: {
    publishers,
  },
} satisfies Meta<typeof PublisherRulesList>

export default meta

export const Example: StoryObj = {
  decorators: [
    Story => (
      <OrganizationAccessPolicyProvider orgDisplayLogin={routePayload.orgDisplayLogin} policy={routePayload.policy}>
        <PublishersProvider models={models} publishers={publishers}>
          <Story />
        </PublishersProvider>
      </OrganizationAccessPolicyProvider>
    ),
    storyWrapper({pathname, routePayload}),
  ],
}

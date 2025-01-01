import type {Meta, StoryObj} from '@storybook/react'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import {accessPolicyShow} from '../routes/access-policy-show-route'
import {OrganizationAccessPolicyProvider} from '../contexts/OrganizationAccessPolicyContext'
import {PublishersProvider} from '../contexts/PublishersContext'
import {mockAccessPolicyShowPayload, mockOrganizationAccessPolicy, mockModel, mockPublisher} from '../test-utils/mocks'
import {ModelsPermissions} from './ModelsPermissions'

const models = [
  mockModel({key: 'foo/bar', publisherId: 1, friendlyName: 'FooBar'}),
  mockModel({key: 'bar/baz', publisherId: 1, friendlyName: 'BarBaz'}),
  mockModel({key: 'baz/bleb', publisherId: 2, friendlyName: 'BazBleb'}),
]
const publishers = [mockPublisher({id: 1, name: 'SomePub'}), mockPublisher({id: 2, name: 'OtherPub'})]
const policy = mockOrganizationAccessPolicy({
  isAllowlist: false,
  isModelsEnabled: true,
  allowedModelKeys: ['foo/bar'],
})
const routePayload = mockAccessPolicyShowPayload({models, policy, publishers})
const pathname = accessPolicyShow.generatePath({org: routePayload.orgDisplayLogin})

const meta = {
  title: 'Apps/GitHub Models org settings/ModelsPermissions',
  component: ModelsPermissions,
  args: {
    models,
    publishers,
  },
} satisfies Meta<typeof ModelsPermissions>

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

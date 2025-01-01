import type {Meta, StoryObj} from '@storybook/react'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import {organizationSettingsModelsAccessPolicyPath} from '@github-ui/paths'
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
const pathname = organizationSettingsModelsAccessPolicyPath({org: routePayload.orgDisplayLogin})

const meta = {
  title: 'Apps/GitHub Models org settings/ModelsPermissions',
  component: ModelsPermissions,
} satisfies Meta

export default meta

export const Example: StoryObj = {
  render: () => <ModelsPermissions />,
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

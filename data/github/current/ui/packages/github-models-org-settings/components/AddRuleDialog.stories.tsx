import type {Meta, StoryObj} from '@storybook/react'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import {accessPolicyShow} from '../routes/access-policy-show-route'
import {OrganizationAccessPolicyProvider} from '../contexts/OrganizationAccessPolicyContext'
import {PublishersProvider} from '../contexts/PublishersContext'
import {SelectionProvider} from '../contexts/SelectionContext'
import {
  mockAccessPolicyShowPayload,
  mockHandlers,
  mockModel,
  mockOrganizationAccessPolicy,
  mockPublisher,
} from '../test-utils/mocks'
import {AddRuleDialog} from './AddRuleDialog'

const models = [
  mockModel({key: 'foo/bar', publisherId: 1, friendlyName: 'FooBar'}),
  mockModel({key: 'bar/baz', publisherId: 1, friendlyName: 'BarBaz'}),
  mockModel({key: 'baz/bleb', publisherId: 2, friendlyName: 'BazBleb'}),
]
const publishers = [
  mockPublisher({id: 1, name: 'SomePub', totalModels: 2}),
  mockPublisher({id: 2, name: 'OtherPub', logoUrl: '/images/modules/marketplace/models/families/meta.svg'}),
]
const policy = mockOrganizationAccessPolicy({isAllowlist: false, allowedModelKeys: ['foo/bar', 'bar/baz']})
const routePayload = mockAccessPolicyShowPayload({models, policy, publishers})
const pathname = accessPolicyShow.generatePath({org: routePayload.orgDisplayLogin})

const meta = {
  title: 'Apps/GitHub Models org settings/AddRuleDialog',
  component: AddRuleDialog,
  args: {
    models,
    publishers,
  },
  parameters: {msw: {handlers: mockHandlers({pathname, initialPolicy: policy, type: 'success'})}},
} satisfies Meta<typeof AddRuleDialog>

export default meta

export const Example: StoryObj = {
  decorators: [
    Story => (
      <OrganizationAccessPolicyProvider orgDisplayLogin={routePayload.orgDisplayLogin} policy={routePayload.policy}>
        <PublishersProvider models={models} publishers={publishers}>
          <SelectionProvider models={models} publishers={publishers}>
            <Story />
          </SelectionProvider>
        </PublishersProvider>
      </OrganizationAccessPolicyProvider>
    ),
    storyWrapper({pathname, routePayload}),
  ],
}

import type {Meta, StoryObj} from '@storybook/react'
import {TreeView} from '@primer/react'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import {accessPolicyShow} from '../routes/access-policy-show-route'
import {OrganizationAccessPolicyProvider} from '../contexts/OrganizationAccessPolicyContext'
import {PublishersProvider} from '../contexts/PublishersContext'
import {SelectionProvider} from '../contexts/SelectionContext'
import {mockAccessPolicyShowPayload, mockModel, mockOrganizationAccessPolicy, mockPublisher} from '../test-utils/mocks'
import {PublisherSelectionItem} from './PublisherSelectionItem'

const models = [
  mockModel({key: 'foo/bar', publisherId: 1, friendlyName: 'Nice Model'}),
  mockModel({key: 'bar/baz', publisherId: 1, friendlyName: 'Fancy Model'}),
  mockModel({key: 'baz/bleb', publisherId: 1, friendlyName: 'Best Model v3'}),
]
const publisher = mockPublisher({id: 1})
const publishers = [publisher]
const policy = mockOrganizationAccessPolicy({
  isAllowlist: false,
  isModelsEnabled: true,
  allowedModelKeys: ['foo/bar'],
})
const routePayload = mockAccessPolicyShowPayload({models, policy, publishers: [publisher]})
const pathname = accessPolicyShow.generatePath({org: routePayload.orgDisplayLogin})

const meta = {
  title: 'Apps/GitHub Models org settings/PublisherSelectionItem',
  component: PublisherSelectionItem,
  args: {publisher, models},
} satisfies Meta<typeof PublisherSelectionItem>

export default meta

type Story = StoryObj<typeof PublisherSelectionItem>

export const Example: Story = {
  decorators: [
    Story => (
      <OrganizationAccessPolicyProvider orgDisplayLogin={routePayload.orgDisplayLogin} policy={routePayload.policy}>
        <PublishersProvider models={models} publishers={publishers}>
          <SelectionProvider models={models} publishers={publishers}>
            <TreeView aria-label="PublisherSelectionItem story tree">
              <Story />
            </TreeView>
          </SelectionProvider>
        </PublishersProvider>
      </OrganizationAccessPolicyProvider>
    ),
    storyWrapper({pathname, routePayload}),
  ],
}

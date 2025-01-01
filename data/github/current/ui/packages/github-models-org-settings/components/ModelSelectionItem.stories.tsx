import type {Meta, StoryObj} from '@storybook/react'
import {TreeView} from '@primer/react'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import {accessPolicyShow} from '../routes/access-policy-show-route'
import {OrganizationAccessPolicyProvider} from '../contexts/OrganizationAccessPolicyContext'
import {PublishersProvider} from '../contexts/PublishersContext'
import {SelectionProvider} from '../contexts/SelectionContext'
import {mockAccessPolicyShowPayload, mockModel, mockOrganizationAccessPolicy, mockPublisher} from '../test-utils/mocks'
import {ModelSelectionItem} from './ModelSelectionItem'

const model = mockModel()
const models = [model]
const publishers = [mockPublisher()]
const policy = mockOrganizationAccessPolicy({isAllowlist: false, isModelsEnabled: true, allowedModelKeys: []})
const routePayload = mockAccessPolicyShowPayload({models, policy})
const pathname = accessPolicyShow.generatePath({org: routePayload.orgDisplayLogin})

const meta = {
  title: 'Apps/GitHub Models org settings/ModelSelectionItem',
  component: ModelSelectionItem,
  args: {model},
} satisfies Meta<typeof ModelSelectionItem>

export default meta

type Story = StoryObj<typeof ModelSelectionItem>

export const Example: Story = {
  decorators: [
    Story => (
      <OrganizationAccessPolicyProvider orgDisplayLogin={routePayload.orgDisplayLogin} policy={routePayload.policy}>
        <PublishersProvider models={models} publishers={publishers}>
          <SelectionProvider models={models} publishers={publishers}>
            <TreeView aria-label="ModelSelectionItem story tree">
              <Story />
            </TreeView>
          </SelectionProvider>
        </PublishersProvider>
      </OrganizationAccessPolicyProvider>
    ),
    storyWrapper({pathname, routePayload}),
  ],
}

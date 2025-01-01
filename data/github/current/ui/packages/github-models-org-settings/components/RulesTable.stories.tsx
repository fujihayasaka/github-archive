import type {Meta, StoryObj} from '@storybook/react'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import {accessPolicyShow} from '../routes/access-policy-show-route'
import {OrganizationAccessPolicyProvider} from '../contexts/OrganizationAccessPolicyContext'
import {PublishersProvider} from '../contexts/PublishersContext'
import {
  mockAccessPolicyShowPayload,
  mockHandlers,
  mockModel,
  mockOrganizationAccessPolicy,
  mockPublisher,
} from '../test-utils/mocks'
import {RulesTable} from './RulesTable'

const models = [mockModel()]
const publishers = [mockPublisher()]
const policy = mockOrganizationAccessPolicy()
const routePayload = mockAccessPolicyShowPayload({policy})
const pathname = accessPolicyShow.generatePath({org: routePayload.orgDisplayLogin})

const meta = {
  title: 'Apps/GitHub Models org settings/RulesTable',
  component: RulesTable,
  args: {
    models,
    publishers,
  },
  parameters: {msw: {handlers: mockHandlers({pathname, initialPolicy: policy, type: 'success'})}},
} satisfies Meta<typeof RulesTable>

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

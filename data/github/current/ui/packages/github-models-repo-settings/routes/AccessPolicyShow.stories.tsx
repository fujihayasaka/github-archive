import type {Meta, StoryObj} from '@storybook/react'
import {repositorySettingsModelsAccessPolicyPath} from '@github-ui/paths'
import {storyWrapper} from '@github-ui/react-core/test-utils'

import {mockAccessPolicyShowPayload, mockHandlers} from '../test-utils/mocks'
import {AccessPolicyShow} from './AccessPolicyShow'

const routePayload = mockAccessPolicyShowPayload()
const pathname = repositorySettingsModelsAccessPolicyPath({
  owner: routePayload.ownerDisplayLogin,
  repo: routePayload.repositoryName,
})

const meta = {
  title: 'Apps/GitHub Models repo settings/AccessPolicyShow',
  component: AccessPolicyShow,
  parameters: {msw: {handlers: mockHandlers({pathname, type: 'success'})}},
} satisfies Meta

export default meta

export const Example: StoryObj = {
  render: () => <AccessPolicyShow />,
  decorators: [storyWrapper({pathname, routePayload})],
}

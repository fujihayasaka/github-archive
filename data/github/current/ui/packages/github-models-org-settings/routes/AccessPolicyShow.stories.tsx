import type {Meta, StoryObj} from '@storybook/react'
import {organizationSettingsModelsAccessPolicyPath} from '@github-ui/paths'
import {storyWrapper} from '@github-ui/react-core/test-utils'

import {AccessPolicyShow} from './AccessPolicyShow'
import {mockAccessPolicyShowPayload, mockHandlers} from '../test-utils/mocks'

const routePayload = mockAccessPolicyShowPayload()
const pathname = organizationSettingsModelsAccessPolicyPath({org: routePayload.orgDisplayLogin})

const meta = {
  title: 'Apps/GitHub Models org settings/AccessPolicyShow',
  component: AccessPolicyShow,
  parameters: {msw: {handlers: mockHandlers({pathname, type: 'success'})}},
} satisfies Meta

export default meta

export const Example: StoryObj = {
  render: () => <AccessPolicyShow />,
  decorators: [storyWrapper({pathname, routePayload})],
}

import type {Meta, StoryContext, StoryFn, StoryObj} from '@storybook/react'
import {organizationSettingsModelsBillingPath} from '@github-ui/paths'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import type {AppPayloadWithFeatureFlags} from '@github-ui/react-core/use-feature-flag'
import {ModelsBilling} from './ModelsBilling'
import {mockAccessPolicyShowPayload, mockBillingHandlers} from '../test-utils/mocks'

const routePayload = mockAccessPolicyShowPayload()
const pathname = organizationSettingsModelsBillingPath({org: routePayload.orgDisplayLogin})

function appPayloadWithEnabledFeature(featureFlag: string): AppPayloadWithFeatureFlags {
  return {enabled_features: {[featureFlag]: true}}
}
const appPayload = appPayloadWithEnabledFeature('github_models_billing_ui')

type Decorator = (fn: StoryFn, c: StoryContext) => JSX.Element

const decorators: Decorator[] = [Story => <Story />, storyWrapper({appPayload, pathname, routePayload})]

const meta = {
  title: 'Apps/GitHub Models org settings/ModelsBilling',
  component: ModelsBilling,
  decorators,
  args: {
    billingEnabled: true,
    orgDisplayLogin: 'my-org',
    canEnableModelsBilling: true,
  },
} satisfies Meta<typeof ModelsBilling>

export default meta

export const SuccessfulRequests: StoryObj = {
  parameters: {msw: {handlers: mockBillingHandlers({pathname, type: 'success'})}},
}

export const FailingRequests: StoryObj = {
  parameters: {msw: {handlers: mockBillingHandlers({pathname, type: 'error'})}},
}

export const InfiniteRequests: StoryObj = {
  parameters: {msw: {handlers: mockBillingHandlers({pathname, type: 'loading'})}},
}

import type {Meta} from '@storybook/react'
import {parametersConfig} from '../utils/story-utils'
import {PaidUsageBanner} from './PaidUsageBanner'
import {Wrapper} from '@github-ui/react-core/test-utils'
import type {UserHookPayload} from '@github-ui/use-user'

const meta = {
  title: 'Apps/GitHub Models/PaidUsageBanner',
  component: PaidUsageBanner,
  parameters: parametersConfig,
} satisfies Meta

export default meta

const currentUser: Partial<UserHookPayload['current_user']> = {
  name: 'Monalisa Octocat',
  avatarUrl: 'https://github.com/octocat.png',
  login: 'octocat',
}

const appPayload = {
  enabled_features: {github_models_billing_ui: true},
  current_user: currentUser,
  repository: {id: 123, isOrgOwned: false, ownerLogin: 'octocat'},
  paidUsageBannerDismissed: false,
}

export const Example = {
  decorators: [
    (Story: React.ComponentType) => (
      <Wrapper appPayload={appPayload}>
        <Story />
      </Wrapper>
    ),
  ],
}

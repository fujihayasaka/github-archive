import type {Meta} from '@storybook/react'
import {
  SecurityCampaignFormContents as SecurityCampaignFormContentsComponent,
  type SecurityCampaignFormContentsProps,
} from '../SecurityCampaignFormContents'
import {SecurityCampaignFormStoryWrapper} from './SecurityCampaignFormStoryWrapper'

const meta = {
  title: 'Security Campaigns/Security Campaign Form Contents',
  component: SecurityCampaignFormContentsComponent,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
  argTypes: {},
} satisfies Meta<typeof SecurityCampaignFormContentsComponent>

export default meta

const defaultArgs: Partial<SecurityCampaignFormContentsProps> = {
  campaignManagersPath: '/github/security-campaigns/security/campaigns/managers',
}

export const SecurityCampaignFormContents = {
  args: defaultArgs,
  render: (args: SecurityCampaignFormContentsProps) => (
    <SecurityCampaignFormStoryWrapper>
      <SecurityCampaignFormContentsComponent {...args} />
    </SecurityCampaignFormStoryWrapper>
  ),
}

export const ShowAutofixPullRequests = {
  args: {
    ...defaultArgs,
    showAutofixPullRequests: true,
  },
  render: (args: SecurityCampaignFormContentsProps) => (
    <SecurityCampaignFormStoryWrapper>
      <SecurityCampaignFormContentsComponent {...args} />
    </SecurityCampaignFormStoryWrapper>
  ),
}

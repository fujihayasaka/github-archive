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
  organizationLogin: 'github',
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

export const ShowGenerateIssues = {
  args: {
    ...defaultArgs,
    showGenerateIssues: true,
  },
  render: (args: SecurityCampaignFormContentsProps) => (
    <SecurityCampaignFormStoryWrapper>
      <SecurityCampaignFormContentsComponent {...args} />
    </SecurityCampaignFormStoryWrapper>
  ),
}

export const ShowAutofixPullRequestsAndGenerateIssues = {
  args: {
    ...defaultArgs,
    showAutofixPullRequests: true,
    showGenerateIssues: true,
  },
  render: (args: SecurityCampaignFormContentsProps) => (
    <SecurityCampaignFormStoryWrapper>
      <SecurityCampaignFormContentsComponent {...args} />
    </SecurityCampaignFormStoryWrapper>
  ),
}

export const ShowDisabledSecurityCampaignFormContents = {
  args: {...defaultArgs, readOnly: true},
  render: (args: SecurityCampaignFormContentsProps) => (
    <SecurityCampaignFormStoryWrapper>
      <SecurityCampaignFormContentsComponent {...args} />
    </SecurityCampaignFormStoryWrapper>
  ),
}

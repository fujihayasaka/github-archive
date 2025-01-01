import type {Meta} from '@storybook/react'
import {
  SecurityCampaignOpenFormContents as SecurityCampaignOpenFormContentsComponent,
  type SecurityCampaignOpenFormContentsProps,
} from './SecurityCampaignOpenFormContents'
import {SecurityCampaignFormStoryWrapper} from '@github-ui/security-campaigns-shared/components/stories/SecurityCampaignFormStoryWrapper'

const meta = {
  title: 'Security Campaigns/Security Campaign Open Form Contents',
  component: SecurityCampaignOpenFormContentsComponent,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
  argTypes: {},
} satisfies Meta<typeof SecurityCampaignOpenFormContentsComponent>

export default meta

const defaultArgs: Partial<SecurityCampaignOpenFormContentsProps> = {
  organizationLogin: 'github',
  maxManagers: 10,
  repositoriesWithIssuesCount: 588,
  repositoriesWithPullRequestsCount: 612,
}

export const Default = {
  args: defaultArgs,
  render: (args: SecurityCampaignOpenFormContentsProps) => (
    <SecurityCampaignFormStoryWrapper>
      <SecurityCampaignOpenFormContentsComponent {...args} />
    </SecurityCampaignFormStoryWrapper>
  ),
}

export const ShowAutofixPullRequests = {
  args: {
    ...defaultArgs,
    showAutofixPullRequests: true,
  },
  render: (args: SecurityCampaignOpenFormContentsProps) => (
    <SecurityCampaignFormStoryWrapper>
      <SecurityCampaignOpenFormContentsComponent {...args} />
    </SecurityCampaignFormStoryWrapper>
  ),
}

export const ShowGenerateIssues = {
  args: {
    ...defaultArgs,
    showGenerateIssues: true,
  },
  render: (args: SecurityCampaignOpenFormContentsProps) => (
    <SecurityCampaignFormStoryWrapper>
      <SecurityCampaignOpenFormContentsComponent {...args} />
    </SecurityCampaignFormStoryWrapper>
  ),
}

export const ShowAutofixPullRequestsAndGenerateIssues = {
  args: {
    ...defaultArgs,
    showAutofixPullRequests: true,
    showGenerateIssues: true,
  },
  render: (args: SecurityCampaignOpenFormContentsProps) => (
    <SecurityCampaignFormStoryWrapper>
      <SecurityCampaignOpenFormContentsComponent {...args} />
    </SecurityCampaignFormStoryWrapper>
  ),
}

export const ShowAutofixPullRequestsAndGenerateIssuesWithoutCounts = {
  args: {
    ...defaultArgs,
    showAutofixPullRequests: true,
    showGenerateIssues: true,
    repositoriesWithIssuesCount: undefined,
    repositoriesWithPullRequestsCount: undefined,
  },
  render: (args: SecurityCampaignOpenFormContentsProps) => (
    <SecurityCampaignFormStoryWrapper>
      <SecurityCampaignOpenFormContentsComponent {...args} />
    </SecurityCampaignFormStoryWrapper>
  ),
}

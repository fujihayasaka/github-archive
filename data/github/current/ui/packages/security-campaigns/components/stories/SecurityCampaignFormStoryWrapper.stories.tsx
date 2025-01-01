import type {Meta} from '@storybook/react'
import {SecurityCampaignFormContents} from '../SecurityCampaignFormContents'
import type {SecurityCampaignFormStoryWrapperProps} from './SecurityCampaignFormStoryWrapper'
import {SecurityCampaignFormStoryWrapper} from './SecurityCampaignFormStoryWrapper'

const meta = {
  title: 'Security Campaigns/Security Campaign Form Story Wrapper',
  component: SecurityCampaignFormStoryWrapper,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
  argTypes: {},
} satisfies Meta<typeof SecurityCampaignFormStoryWrapper>

export default meta

export const SecurityCampaignFormWrapperExample = {
  args: {},
  render: (args: SecurityCampaignFormStoryWrapperProps) => (
    <SecurityCampaignFormStoryWrapper {...args}>
      <SecurityCampaignFormContents organizationLogin="github" maxManagers={10} />
    </SecurityCampaignFormStoryWrapper>
  ),
}

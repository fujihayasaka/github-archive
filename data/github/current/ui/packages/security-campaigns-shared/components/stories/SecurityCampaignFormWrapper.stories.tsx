import type {Meta} from '@storybook/react'
import {getUser} from '../../test-utils/mock-data'
import {SecurityCampaignFormContents} from '../SecurityCampaignFormContents'
import {SecurityCampaignFormWrapper, type SecurityCampaignFormWrapperProps} from '../SecurityCampaignFormWrapper'
import {TestWrapper} from '../../test-utils/TestWrapper'

const meta = {
  title: 'Security Campaigns/Security Campaign Form Wrapper',
  component: SecurityCampaignFormWrapper,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
  argTypes: {},
} satisfies Meta<typeof SecurityCampaignFormWrapper>

export default meta

const defaultArgs: Partial<SecurityCampaignFormWrapperProps> = {
  campaign: undefined,
  currentUser: getUser(),
  allowDueDateInPast: false,
  submitForm: () => {},
  reset: () => {},
  isPending: false,
  formError: null,
}

export const SecurityCampaignFormWrapperExample = {
  args: defaultArgs,
  render: (args: SecurityCampaignFormWrapperProps) => (
    <TestWrapper>
      <SecurityCampaignFormWrapper {...args}>
        <SecurityCampaignFormContents campaignManagersPath="/github/security-campaigns/security/campaigns/managers" />
      </SecurityCampaignFormWrapper>
    </TestWrapper>
  ),
}

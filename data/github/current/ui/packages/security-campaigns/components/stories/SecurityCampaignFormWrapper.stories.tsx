import type {Meta} from '@storybook/react'
import {SecurityCampaignFormContents} from '../SecurityCampaignFormContents'
import {SecurityCampaignFormWrapper, type SecurityCampaignFormWrapperProps} from '../SecurityCampaignFormWrapper'
import {getUser} from '../../test-utils/mock-data'

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
  initialValues: undefined,
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
    <SecurityCampaignFormWrapper {...args}>
      <SecurityCampaignFormContents organizationLogin="github" maxManagers={10} />
    </SecurityCampaignFormWrapper>
  ),
}

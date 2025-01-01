import {disableA11yRuleForDialog} from '@github-ui/react-core/test-utils'
import type {Meta} from '@storybook/react'
import {
  EditSecurityCampaignFormDialog,
  type EditSecurityCampaignFormDialogProps,
} from './EditSecurityCampaignFormDialog'
import {getSecurityCampaign} from '../test-utils/mock-data'

const meta = {
  title: 'Security Campaigns/Security Campaign Form Dialog',
  component: EditSecurityCampaignFormDialog,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
    a11y: disableA11yRuleForDialog,
  },
  argTypes: {},
} satisfies Meta<typeof EditSecurityCampaignFormDialog>

export default meta

const defaultArgs: Partial<EditSecurityCampaignFormDialogProps> = {
  organizationLogin: 'github',
  securityCampaignNumber: 5,
  setIsOpen: () => undefined,
  campaign: getSecurityCampaign(),
  submitForm: () => Promise.resolve({ok: true}),
}

export const UpdateExistingCampaign = {
  args: {
    ...defaultArgs,
    allowDueDateInPast: true,
  },
  render: (args: EditSecurityCampaignFormDialogProps) => <EditSecurityCampaignFormDialog {...args} />,
}

export const CampaignDetails = {
  args: {
    ...defaultArgs,
    readOnly: true,
  },
  render: (args: EditSecurityCampaignFormDialogProps) => <EditSecurityCampaignFormDialog {...args} />,
}

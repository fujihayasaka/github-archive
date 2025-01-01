import type {Meta} from '@storybook/react'
import {disableA11yRuleForDialog} from '@github-ui/react-core/test-utils'
import {
  DeleteCampaignConfirmationDialog,
  type DeleteCampaignConfirmationDialogProps,
} from '../DeleteCampaignConfirmationDialog'

const meta = {
  title: 'Apps/Security Campaigns/Delete security campaign confirmation dialog',
  component: DeleteCampaignConfirmationDialog,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
    a11y: disableA11yRuleForDialog,
  },
  argTypes: {},
} satisfies Meta<typeof DeleteCampaignConfirmationDialog>

export default meta

const defaultArgs: Partial<DeleteCampaignConfirmationDialogProps> = {
  setIsOpen: () => undefined,
  deleteCampaign: () => undefined,
}

export const DeleteSecurityCampaignConfirmationDialog = {
  args: defaultArgs,
  render: (args: DeleteCampaignConfirmationDialogProps) => <DeleteCampaignConfirmationDialog {...args} />,
}

export const DeleteDraftSecurityCampaignConfirmationDialog = {
  args: {...defaultArgs, isDraft: true, campaignName: 'SQL injection'},
  render: (args: DeleteCampaignConfirmationDialogProps) => <DeleteCampaignConfirmationDialog {...args} />,
}

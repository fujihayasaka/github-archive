import {disableA11yRuleForDialog} from '@github-ui/react-core/test-utils'
import type {Meta} from '@storybook/react'
import {
  UpsertDraftSecurityCampaignFormDialog,
  type UpsertDraftSecurityCampaignFormDialogProps,
} from './UpsertDraftSecurityCampaignFormDialog'
import {getSecurityCampaign, getUser} from '../test-utils/mock-data'

const meta = {
  title: 'Security Campaigns/Upsert Draft Security Campaign Form Dialog',
  component: UpsertDraftSecurityCampaignFormDialog,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
    a11y: disableA11yRuleForDialog,
  },
  argTypes: {},
} satisfies Meta<typeof UpsertDraftSecurityCampaignFormDialog>

export default meta

const defaultArgs: UpsertDraftSecurityCampaignFormDialogProps = {
  organizationLogin: 'github',
  currentUser: getUser(),
  setIsOpen: () => undefined,
  submitForm: () => Promise.resolve({ok: true}),
  isPending: false,
  formError: null,
  resetForm: () => undefined,
  maxManagers: 10,
}

export const NewDraftCampaign = {
  args: defaultArgs,
  render: (args: UpsertDraftSecurityCampaignFormDialogProps) => <UpsertDraftSecurityCampaignFormDialog {...args} />,
}

export const NewDraftCampaignFromTemplate = {
  args: {...defaultArgs, campaignTemplateName: 'Test Template', campaignTemplateDescription: 'Test Description'},
  render: (args: UpsertDraftSecurityCampaignFormDialogProps) => <UpsertDraftSecurityCampaignFormDialog {...args} />,
}

export const EditDraftCampaign = {
  args: {...defaultArgs, campaign: getSecurityCampaign({publishedAt: undefined})},
  render: (args: UpsertDraftSecurityCampaignFormDialogProps) => <UpsertDraftSecurityCampaignFormDialog {...args} />,
}

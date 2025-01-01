import type {Meta} from '@storybook/react'
import {
  EditSecurityCampaignFormDialog,
  type EditSecurityCampaignFormDialogProps,
} from './EditSecurityCampaignFormDialog'
import {getSecurityCampaign} from '@github-ui/security-campaigns-shared/test-utils/mock-data'
import {QueryClientProvider} from '@tanstack/react-query'
import {getQueryClient} from '@github-ui/security-campaigns-shared/utils/query-client'

const meta = {
  title: 'Security Campaigns/Security Campaign Form Dialog',
  component: EditSecurityCampaignFormDialog,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
  argTypes: {},
} satisfies Meta<typeof EditSecurityCampaignFormDialog>

export default meta

const defaultArgs: Partial<EditSecurityCampaignFormDialogProps> = {
  setIsOpen: () => undefined,
  campaign: getSecurityCampaign(),
  submitForm: () => Promise.resolve({ok: true}),
}

export const UpdateExistingCampaign = {
  args: {
    ...defaultArgs,
    allowDueDateInPast: true,
  },
  render: (args: EditSecurityCampaignFormDialogProps) => (
    <QueryClientProvider client={getQueryClient()}>
      <EditSecurityCampaignFormDialog {...args} />
    </QueryClientProvider>
  ),
}

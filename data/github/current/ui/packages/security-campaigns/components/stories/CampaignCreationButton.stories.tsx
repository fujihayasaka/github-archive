import type {Meta} from '@storybook/react'
import {CampaignCreationButton, type CampaignCreationButtonProps} from '../CampaignCreationButton'
import {Wrapper} from '@github-ui/react-core/test-utils'

const meta = {
  title: 'Apps/Security Campaigns/Campaign Creation Button',
  component: CampaignCreationButton,

  argTypes: {},
} satisfies Meta<typeof CampaignCreationButton>

export default meta

const defaultArgs: Partial<CampaignCreationButtonProps> = {
  organizationLogin: 'octodemo',
  maxCampaignsReached: false,
  maxOpenCampaigns: 10,
  maxDraftCampaigns: 10,
  setIsTemplatesDialogOpen: () => {},
}

export const Default = {
  args: defaultArgs,
  render: (args: CampaignCreationButtonProps) => (
    <Wrapper>
      <CampaignCreationButton {...args} />
    </Wrapper>
  ),
}

export const MaxCampaignsReached = {
  args: {...defaultArgs, maxCampaignsReached: true},
  render: (args: CampaignCreationButtonProps) => (
    <Wrapper>
      <CampaignCreationButton {...args} />
    </Wrapper>
  ),
}

import type {Meta} from '@storybook/react'
import {NoCampaignsBlankSlate, type NoCampaignsBlankSlateProps} from '../NoCampaignsBlankSlate'
import {Wrapper} from '@github-ui/react-core/test-utils'

const meta = {
  title: 'Apps/Security Campaigns/No Campaigns Blank Slate',
  component: NoCampaignsBlankSlate,
  argTypes: {},
} satisfies Meta<typeof NoCampaignsBlankSlate>

export default meta

const defaultArgs: Partial<NoCampaignsBlankSlateProps> = {
  creationAllowed: true,
  organizationLogin: 'octodemo',
  maxCampaignsReached: false,
  maxOpenCampaigns: 10,
  maxDraftCampaigns: 10,
  setIsTemplatesDialogOpen: () => {},
  aboutCampaignsDocsUrl: 'https://github.com',
}

export const CreationAllowed = {
  args: defaultArgs,
  render: (args: NoCampaignsBlankSlateProps) => (
    <Wrapper>
      <NoCampaignsBlankSlate {...args} />
    </Wrapper>
  ),
}

export const CreationNotAllowed = {
  args: {...defaultArgs, creationAllowed: false},
  render: (args: NoCampaignsBlankSlateProps) => (
    <Wrapper>
      <NoCampaignsBlankSlate {...args} />
    </Wrapper>
  ),
}

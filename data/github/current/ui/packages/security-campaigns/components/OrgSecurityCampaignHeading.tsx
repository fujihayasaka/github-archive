import {Heading, StateLabel, Stack} from '@primer/react'
import {CampaignContactLink} from './CampaignContactLink'
import {CampaignManagersText} from './CampaignManagersText'
import type {Team} from '../types/team'
import type {User} from '../types/user'

export interface OrgSecurityCampaignHeadingProps {
  campaignName: string
  userManagers: User[]
  teamManagers: Team[]
  contactLink: string | null
  isDraft: boolean
}

export function OrgSecurityCampaignHeading({
  campaignName,
  userManagers,
  teamManagers,
  contactLink,
  isDraft,
}: OrgSecurityCampaignHeadingProps) {
  return (
    <Stack gap="condensed" data-testid="campaign-heading">
      <Heading data-hpc as="h2" className={`f2 text-normal mt-2 ${isDraft ? 'fgColor-muted' : ''}`}>
        {isDraft && (
          <StateLabel status="issueDraft" className="fgColor-muted bgColor-default mr-1">
            Draft
          </StateLabel>
        )}
        {campaignName}
      </Heading>
      <div className={`mb-1 ${isDraft ? 'fgColor-muted' : ''}`}>
        <CampaignManagersText managers={userManagers} teamManagers={teamManagers} />
        <CampaignContactLink
          contactLink={contactLink}
          teamCount={teamManagers.length}
          userCount={userManagers.length}
        />
      </div>
    </Stack>
  )
}

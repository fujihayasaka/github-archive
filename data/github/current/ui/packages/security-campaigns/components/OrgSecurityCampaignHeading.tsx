import {Box, Heading, StateLabel} from '@primer/react'
import {CampaignContactLink} from './CampaignContactLink'
import {CampaignManagersText} from './CampaignManagersText'
import type {User} from '@github-ui/security-campaigns-shared/types/user'
import type {Team} from '../../security-campaigns-shared/types/team'

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
    <Box sx={{display: 'flex', flexDirection: 'column', gap: 2}} data-testid="campaign-heading">
      <Heading data-hpc as="h2" className="f2 text-normal">
        {isDraft && (
          <StateLabel status="issueDraft" className="fgColor-muted bgColor-default mr-1">
            Draft
          </StateLabel>
        )}
        {campaignName}
      </Heading>
      <div>
        <CampaignManagersText managers={userManagers} teamManagers={teamManagers} />
        <CampaignContactLink contactLink={contactLink} />
      </div>
    </Box>
  )
}

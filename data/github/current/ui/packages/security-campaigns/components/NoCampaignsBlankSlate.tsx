import {GoalIcon} from '@primer/octicons-react'
import {Box, Link} from '@primer/react'
import {Blankslate} from '@primer/react/experimental'

import {CampaignCreationButton} from './CampaignCreationButton'

import styles from './NoCampaignsBlankSlate.module.css'

export type NoCampaignsBlankSlateProps = {
  creationAllowed: boolean
  organizationLogin: string
  maxCampaignsReached: boolean
  maxOpenCampaigns: number
  maxDraftCampaigns: number
  setIsTemplatesDialogOpen: (isOpen: boolean) => void
  aboutCampaignsDocsUrl: string
  draftCampaignsEnabled: boolean
}

export const NoCampaignsBlankSlate = ({
  creationAllowed,
  organizationLogin,
  maxCampaignsReached,
  maxOpenCampaigns,
  maxDraftCampaigns,
  setIsTemplatesDialogOpen,
  aboutCampaignsDocsUrl,
  draftCampaignsEnabled,
}: NoCampaignsBlankSlateProps) => {
  if (!creationAllowed) {
    return (
      <Box sx={{borderWidth: 1, borderStyle: 'solid', borderRadius: 2, borderColor: 'border.default', pt: 2, mb: 3}}>
        <Blankslate spacious>
          <Blankslate.Visual>
            <GoalIcon size="medium" />
          </Blankslate.Visual>
          <Blankslate.Heading>No campaigns available</Blankslate.Heading>
          <Blankslate.Description>
            Security campaigns help teams remediate code scanning alerts with the help of Copilot Autofix.
            <br />
            <Link inline href={aboutCampaignsDocsUrl}>
              Learn more about security campaigns
            </Link>
          </Blankslate.Description>
        </Blankslate>
      </Box>
    )
  }

  return (
    <Box sx={{borderWidth: 1, borderStyle: 'solid', borderRadius: 2, borderColor: 'border.default', pt: 2, mb: 3}}>
      <Blankslate spacious>
        <Blankslate.Visual>
          <GoalIcon size="medium" />
        </Blankslate.Visual>
        <Blankslate.Heading>Start a new campaign</Blankslate.Heading>
        <Blankslate.Description>
          Start a new security campaign to help teams remediate code scanning alerts with the help of Copilot Autofix.
          <br />
          <Link inline href={aboutCampaignsDocsUrl}>
            Learn more about security campaigns
          </Link>
        </Blankslate.Description>
        <div className={styles.Action}>
          <CampaignCreationButton
            organizationLogin={organizationLogin}
            maxCampaignsReached={maxCampaignsReached}
            maxOpenCampaigns={maxOpenCampaigns}
            maxDraftCampaigns={maxDraftCampaigns}
            setIsTemplatesDialogOpen={setIsTemplatesDialogOpen}
            draftCampaignsEnabled={draftCampaignsEnabled}
          />
        </div>
      </Blankslate>
    </Box>
  )
}

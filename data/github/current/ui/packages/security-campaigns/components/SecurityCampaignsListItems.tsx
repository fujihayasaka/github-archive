import {RowsLoading} from './RowsLoading'
import {Blankslate} from '@primer/react/experimental'
import {AlertIcon} from '@primer/octicons-react'
import {SecurityCampaignListItem} from './SecurityCampaignListItem'
import {BlankslateListItem} from './BlankslateListItem'
import type {SecurityCampaignState} from '../types/security-campaign-state'
import type {SecurityCampaign, SecurityCampaignWithCounts} from '../types/security-campaign'

export interface SecurityCampaignsListItemsProps {
  organizationLogin: string
  campaigns: SecurityCampaignWithCounts[] | SecurityCampaign[]
  campaignState: SecurityCampaignState
  openCampaignsCount: number
  maxOpenCampaigns: number
  hasOpenSpam: boolean
  allowActions: boolean
  isPending: boolean
  isError: boolean
  onMutationError: (error: string) => void
  showLeadingIcon?: boolean
  showManagers?: boolean
}

export function SecurityCampaignsListItems({
  organizationLogin,
  campaigns,
  campaignState,
  maxOpenCampaigns,
  openCampaignsCount,
  hasOpenSpam,
  allowActions,
  isPending,
  isError,
  onMutationError,
  showLeadingIcon = false,
  showManagers = false,
}: SecurityCampaignsListItemsProps) {
  if (isPending) {
    return <RowsLoading rowCount={5} />
  }

  if (isError) {
    return (
      <BlankslateListItem>
        <Blankslate.Visual>
          <AlertIcon size={'medium'} />
        </Blankslate.Visual>
        <Blankslate.Heading>An error has occurred.</Blankslate.Heading>
        <Blankslate.Description>{`${capitalizeFirstLetter(
          campaignState,
        )} campaigns data could not be loaded right now.`}</Blankslate.Description>
      </BlankslateListItem>
    )
  }

  if (campaigns.length === 0) {
    return (
      <BlankslateListItem spacious>
        <Blankslate.Heading>{`This organization has no ${campaignState} campaigns`}</Blankslate.Heading>
      </BlankslateListItem>
    )
  }

  return campaigns.map(campaign => (
    <SecurityCampaignListItem
      key={campaign.id}
      organizationLogin={organizationLogin}
      maxOpenCampaigns={maxOpenCampaigns}
      openCampaignsCount={openCampaignsCount}
      campaign={campaign}
      hasOpenSpam={hasOpenSpam}
      allowActions={allowActions}
      showLeadingIcon={showLeadingIcon}
      showManagers={showManagers}
      onMutationError={onMutationError}
    />
  ))
}

export function capitalizeFirstLetter(string: string): string {
  return string.charAt(0).toUpperCase() + string.slice(1)
}

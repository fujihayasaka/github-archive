import {RowsLoading} from './RowsLoading'
import {Blankslate} from '@primer/react/experimental'
import {AlertIcon} from '@primer/octicons-react'
import type {SecurityCampaignWithCounts} from '@github-ui/security-campaigns-shared/SecurityCampaign'
import {ClosedSecurityCampaignListItem} from './ClosedSecurityCampaignListItem'
import {BlankslateListItem} from './BlankslateListItem'

export interface ClosedSecurityCampaignsListItemsProps {
  campaigns: SecurityCampaignWithCounts[]
  isPending: boolean
  isError: boolean
  onMutationError: (error: string) => void
}

export function ClosedSecurityCampaignsListItems({
  campaigns,
  isPending,
  isError,
  onMutationError,
}: ClosedSecurityCampaignsListItemsProps) {
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
        <Blankslate.Description>Closed campaigns data could not be loaded right now.</Blankslate.Description>
      </BlankslateListItem>
    )
  }

  if (campaigns.length === 0) {
    return (
      <BlankslateListItem spacious>
        <Blankslate.Heading>This organization has no closed campaigns</Blankslate.Heading>
      </BlankslateListItem>
    )
  }

  return campaigns.map(campaign => (
    <ClosedSecurityCampaignListItem key={campaign.id} campaign={campaign} onMutationError={onMutationError} />
  ))
}

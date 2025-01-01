import {ListView} from '@github-ui/list-view'
import {ListViewMetadata} from '@github-ui/list-view/ListViewMetadata'
import {Box, Flash} from '@primer/react'
import {PrevNextPagination} from './PrevNextPagination'
import {SecurityCampaignsListItems} from './SecurityCampaignsListItems'
import {useCallback, useMemo, useState} from 'react'
import {number as formatNumber} from '@github-ui/formatters'
import {useCampaignsQuery} from '../hooks/use-campaigns-query'
import {ListViewSectionFilterLink} from '@github-ui/list-view/ListViewSectionFilterLink'
import type {SecurityCampaignState} from '../types/security-campaign-state'
import {orderOpenCampaignsList} from '../utils/order-open-campaigns-list'
import {useCampaignsParams} from '../hooks/use-campaigns-params'

export interface SecurityCampaignsProps {
  openCount: number
  closedCount: number
  draftCount: number
  showFullView: boolean
  organizationLogin: string
  maxOpenCampaigns: number
  draftCampaignsEnabled: boolean
}

export function SecurityCampaignsList({
  openCount,
  closedCount,
  draftCount,
  showFullView,
  organizationLogin,
  maxOpenCampaigns,
  draftCampaignsEnabled,
}: SecurityCampaignsProps) {
  const {campaignState, cursor, onCampaignStateChange, onCursorChange} = useCampaignsParams()
  const campaignsQuery = useCampaignsQuery(organizationLogin, {cursor, state: campaignState})

  const [mutationErrors, setMutationErrors] = useState<string[]>([])
  const handleNewMutationError = useCallback((error: string) => {
    setMutationErrors(errors => [...errors, error])
  }, [])

  const onSectionFilterClicked = useCallback(
    (event: React.MouseEvent, state: SecurityCampaignState) => {
      event.preventDefault()
      onCampaignStateChange(state)
    },
    [onCampaignStateChange],
  )

  const filters = showFullView
    ? [
        <ListViewSectionFilterLink
          key="open"
          title="Open"
          href="#"
          count={formatNumber(openCount)}
          onClick={e => onSectionFilterClicked(e, 'open')}
          isSelected={campaignState === 'open'}
          isLoading={campaignsQuery.isLoading}
        />,

        <ListViewSectionFilterLink
          key="closed"
          title="Closed"
          href="#"
          count={formatNumber(closedCount)}
          onClick={e => onSectionFilterClicked(e, 'closed')}
          isSelected={campaignState === 'closed'}
          isLoading={campaignsQuery.isLoading}
        />,
        draftCampaignsEnabled && (
          <ListViewSectionFilterLink
            key="draft"
            title="Draft"
            href="#"
            count={formatNumber(draftCount)}
            onClick={e => onSectionFilterClicked(e, 'draft')}
            isSelected={campaignState === 'draft'}
            isLoading={campaignsQuery.isLoading}
          />
        ),
      ].filter(item => typeof item !== 'boolean')
    : []

  const campaigns = useMemo(() => {
    if (!campaignsQuery.data || !campaignsQuery.data.campaigns || campaignsQuery.data.campaigns.length === 0) {
      return []
    }

    // For open campaigns we want to re-order the list.
    if (campaignState === 'open') {
      return orderOpenCampaignsList(campaignsQuery.data.campaigns)
    }

    // For closed and draft campaigns we want to just render the list of campaigns
    // as returned by the API.
    return campaignsQuery.data.campaigns
  }, [campaignState, campaignsQuery.data])

  return (
    <>
      {mutationErrors.map(message => (
        <Flash key={message} variant="danger" sx={{mb: 2}}>
          {message}
        </Flash>
      ))}
      <Box
        sx={{
          borderWidth: 1,
          borderStyle: 'solid',
          borderRadius: 2,
          borderColor: 'border.default',
          overflow: 'hidden',
          mb: 3,
        }}
      >
        <ListView
          metadata={<ListViewMetadata className="rounded-top-2" sectionFilters={filters} />}
          title="Campaigns"
          titleHeaderTag="h3"
          totalCount={openCount + closedCount}
        >
          <SecurityCampaignsListItems
            organizationLogin={organizationLogin}
            campaigns={campaigns}
            campaignState={campaignState}
            maxOpenCampaigns={maxOpenCampaigns}
            openCampaignsCount={openCount}
            allowActions={showFullView}
            isPending={campaignsQuery.isLoading}
            isError={campaignsQuery.isError}
            onMutationError={handleNewMutationError}
            showLeadingIcon
            showManagers
          />
        </ListView>
      </Box>

      <PrevNextPagination
        onCursorChange={onCursorChange}
        prevCursor={campaignsQuery.data?.prevCursor}
        nextCursor={campaignsQuery.data?.nextCursor}
      />
    </>
  )
}

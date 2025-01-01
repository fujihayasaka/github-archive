import {ListView} from '@github-ui/list-view'
import {ListViewMetadata} from '@github-ui/list-view/ListViewMetadata'
import {number as formatNumber} from '@github-ui/formatters'
import {Box, Flash, Text} from '@primer/react'
import pluralize from 'pluralize'
import {PrevNextPagination} from '../components/PrevNextPagination'
import {SecurityCampaignsListItems} from './SecurityCampaignsListItems'
import type {Cursor} from '../types/cursor'
import {useCallback, useState} from 'react'
import {useClosedCampaignsQuery} from '../hooks/use-closed-campaigns-query'

export interface ClosedSecurityCampaignsProps {
  organizationLogin: string
  closedCampaignsCounts: number
  closedCampaignsPath: string
  openCampaignsCounts: number
  maxOpenCampaigns: number
}

export function ClosedSecurityCampaignsList({
  organizationLogin,
  closedCampaignsCounts,
  closedCampaignsPath,
  openCampaignsCounts,
  maxOpenCampaigns,
}: ClosedSecurityCampaignsProps) {
  const [cursor, setCursor] = useState<Cursor | null>(null)

  const response = useClosedCampaignsQuery(closedCampaignsPath, {cursor})

  const [mutationErrors, setMutationErrors] = useState<string[]>([])
  const handleNewMutationError = useCallback((error: string) => {
    setMutationErrors(errors => [...errors, error])
  }, [])

  return (
    <>
      {mutationErrors.map(message => (
        <Flash key={message} variant="danger" sx={{mb: 2}}>
          {message}
        </Flash>
      ))}
      <Box sx={{borderWidth: 1, borderStyle: 'solid', borderRadius: 2, borderColor: 'border.default', mb: 3}}>
        <ListView
          metadata={
            <ListViewMetadata
              className="rounded-top-2"
              title={
                <Text sx={{fontWeight: 'bold'}}>
                  {formatNumber(closedCampaignsCounts)} closed {pluralize('campaign', closedCampaignsCounts)}
                </Text>
              }
            />
          }
          title="Closed campaigns"
          titleHeaderTag="h3"
          totalCount={closedCampaignsCounts}
        >
          <SecurityCampaignsListItems
            organizationLogin={organizationLogin}
            campaigns={response.data?.campaigns || []}
            campaignState="closed"
            maxOpenCampaigns={maxOpenCampaigns}
            openCampaignsCount={openCampaignsCounts}
            allowActions
            isPending={response.isLoading}
            isError={response.isError}
            onMutationError={handleNewMutationError}
          />
        </ListView>
      </Box>

      <PrevNextPagination
        onCursorChange={setCursor}
        prevCursor={response.data?.prevCursor}
        nextCursor={response.data?.nextCursor}
      />
    </>
  )
}

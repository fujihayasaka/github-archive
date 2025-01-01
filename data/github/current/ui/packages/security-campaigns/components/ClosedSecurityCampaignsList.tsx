import {ListView} from '@github-ui/list-view'
import {ListViewMetadata} from '@github-ui/list-view/ListViewMetadata'
import {Box, Flash, Text} from '@primer/react'
import pluralize from 'pluralize'
import {PrevNextPagination} from '../components/PrevNextPagination'
import {ClosedSecurityCampaignsListItems} from '../components/ClosedSecurityCampaignsListItems'
import type {GetClosedCampaignsCursor} from '../types/get-closed-campaigns-request'
import {useCallback, useState} from 'react'
import {useClosedCampaignsQuery} from '../hooks/use-closed-campaigns-query'

export interface ClosedSecurityCampaignsProps {
  closedCampaignsCounts: number
  closedCampaignsPath: string
}

export function ClosedSecurityCampaignsList({
  closedCampaignsCounts,
  closedCampaignsPath,
}: ClosedSecurityCampaignsProps) {
  const [cursor, setCursor] = useState<GetClosedCampaignsCursor | null>(null)

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
                  {closedCampaignsCounts} closed {pluralize('campaign', closedCampaignsCounts)}
                </Text>
              }
            />
          }
          title="Closed campaigns"
          titleHeaderTag="h3"
          totalCount={closedCampaignsCounts}
        >
          <ClosedSecurityCampaignsListItems
            campaigns={response.data?.campaigns || []}
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

import {Filter, type FilterProvider} from '@github-ui/filter'
import {useSyncedState} from '@github-ui/use-synced-state'

import styles from './OrgAlertsFilter.module.css'
import {Button, Flash, Stack} from '@primer/react'
import type {SecurityCampaign} from '@github-ui/security-campaigns-shared/SecurityCampaign'
import {useEditDraftSecurityCampaignMutation} from '../hooks/use-edit-draft-security-campaign-mutation'

export type OrgDraftAlertsFilterProps = {
  providers: FilterProvider[]
  query: string
  setQuery: (query: string) => void
  campaign: SecurityCampaign
  setCampaign: (campaign: SecurityCampaign) => void
  organizationLogin: string
}

export const OrgDraftAlertsFilter = ({
  providers,
  query,
  setQuery,
  campaign,
  setCampaign,
  organizationLogin,
}: OrgDraftAlertsFilterProps) => {
  const [filterValue, setFilterValue] = useSyncedState(query)

  const {
    mutate: mutateEdit,
    error,
    isPending,
  } = useEditDraftSecurityCampaignMutation(organizationLogin, campaign.number)

  const editCampaignQuery = (newQuery: string) => {
    mutateEdit(
      {
        campaignName: campaign.name,
        campaignDescription: campaign.description,
        campaignManagers: campaign.managers.map(user => user.id),
        campaignTeamManagers: campaign.teamManagers.map(team => team.id),
        campaignContactLink: campaign.contactLink,
        query: newQuery,
      },
      {
        onSuccess: () => {
          setCampaign({...campaign, creationQuery: newQuery})
        },
      },
    )
  }

  return (
    <>
      <Stack gap="condensed" direction="horizontal" className="my-2">
        <div className="width-full">
          <Filter
            id="security-campaign-org-alerts-filter"
            label="Filter"
            placeholder="Filter"
            providers={providers}
            filterValue={filterValue}
            onChange={setFilterValue}
            onSubmit={request => setQuery(request.raw)}
            className={styles.Filter_0}
          />
        </div>
        <Button size="small" disabled={isPending} onClick={() => setFilterValue(campaign.creationQuery ?? 'is:open')}>
          Discard
        </Button>
        <Button
          loading={isPending}
          disabled={isPending}
          onClick={() => editCampaignQuery(filterValue)}
          variant="primary"
          size="small"
        >
          Save
        </Button>
      </Stack>

      {error && (
        <Flash variant="danger" className="mb-2">
          {error.message}
        </Flash>
      )}
    </>
  )
}

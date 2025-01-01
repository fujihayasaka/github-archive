import {Filter, type FilterProvider} from '@github-ui/filter'
import styles from './OrgAlertsFilter.module.css'
import {Button, Flash, Stack} from '@primer/react'
import {useEditDraftSecurityCampaignMutation} from '../hooks/use-edit-draft-security-campaign-mutation'
import type {SecurityCampaign} from '../types/security-campaign'

export type OrgDraftAlertsFilterProps = {
  providers: FilterProvider[]
  setQuery: (query: string) => void
  campaign: SecurityCampaign
  setCampaign: (campaign: SecurityCampaign) => void
  organizationLogin: string
  filterValue: string
  setFilterValue: (filterValue: string) => void
}

export const OrgDraftAlertsFilter = ({
  providers,
  setQuery,
  campaign,
  setCampaign,
  organizationLogin,
  filterValue,
  setFilterValue,
}: OrgDraftAlertsFilterProps) => {
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

  const queryHasChanged = filterValue.trim() !== (campaign.creationQuery ?? '').trim()
  const disabled = isPending || !queryHasChanged

  return (
    <>
      <Stack gap="condensed" direction="horizontal" className="my-3">
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
        <Button
          size="small"
          disabled={disabled}
          onClick={() => {
            setFilterValue(campaign.creationQuery ?? 'is:open')
            setQuery(campaign.creationQuery ?? 'is:open')
          }}
        >
          Discard
        </Button>
        <Button
          loading={isPending}
          disabled={disabled}
          onClick={() => {
            editCampaignQuery(filterValue)
            setQuery(filterValue)
          }}
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

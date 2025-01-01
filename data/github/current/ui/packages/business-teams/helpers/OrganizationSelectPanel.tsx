import {useState} from 'react'
import {ActionList, Box, Button, CounterLabel, Spinner, Tooltip} from '@primer/react'
import {Banner, SelectPanel} from '@primer/react/experimental'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {OrganizationIcon, TriangleDownIcon} from '@primer/octicons-react'
import styles from '../styles/BusinessTeamsCreateEditView.module.css'
import {useQuery} from '@github-ui/react-query'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {useDebounce} from '@github-ui/use-debounce'
import type {Organization} from '../types'

export interface OrganizationSuggestions {
  organizations: Organization[]
  totalAvailableCount: number
}

export interface OrganizationSelectPanelProps {
  enterpriseSlug: string
  initialSelectedIds: number[]
  onOrganizationsAdded: (addedOrganizations: Organization[]) => void
  enterpriseTeamsOrgAssignmentLimit: number
}

export function OrganizationSelectPanel({
  enterpriseSlug,
  initialSelectedIds,
  onOrganizationsAdded,
  enterpriseTeamsOrgAssignmentLimit,
}: OrganizationSelectPanelProps) {
  const [debouncedFilter, setDebouncedFilter] = useState('')
  const [isSelectPanelOpen, setSelectPanelOpen] = useState(false)

  const {
    isError: searchQueryError,
    isPending: searchQueryPending,
    data: searchResults,
  } = useQuery<OrganizationSuggestions>({
    queryKey: ['eligibleOrganizations', enterpriseSlug, debouncedFilter, initialSelectedIds],
    queryFn: async () => {
      // We use a post to avoid being bounded by query string limit with the org list.
      const response = await verifiedFetchJSON(`/enterprises/${enterpriseSlug}/organization_suggestions`, {
        method: 'POST',
        headers: {Accept: 'application/json'},
        body: {
          query: debouncedFilter,
          selectedOrganizationIds: initialSelectedIds,
        },
      })

      if (response.ok) {
        return await response.json()
      } else {
        throw new Error(`${response.status} on ${response.url}`)
      }
    },
    enabled: isSelectPanelOpen,
  })
  const eligibleOrganizations: Organization[] = searchResults?.organizations || []

  const [addingSelectedOrganizations, setAddingSelectedOrganizations] = useState<Organization[]>([])
  const [filter, setFilter] = useState('')

  const assignmentAllowedToAddLimitReached =
    initialSelectedIds.length + addingSelectedOrganizations.length >= enterpriseTeamsOrgAssignmentLimit

  eligibleOrganizations.sort((a, b) => {
    const aIsSelected = addingSelectedOrganizations.includes(a)
    const bIsSelected = addingSelectedOrganizations.includes(b)
    if (aIsSelected && !bIsSelected) return -1
    if (!aIsSelected && bIsSelected) return 1
    return 0
  })

  function handleAddOrganizations() {
    onOrganizationsAdded(addingSelectedOrganizations)
    handleCancel()
  }

  function handleCancel() {
    setAddingSelectedOrganizations([])
    setSelectPanelOpen(false)
  }

  function handleFilterChange(newFilter: string) {
    setFilter(newFilter)
    updateDebouncedFilter(newFilter)
  }

  const updateDebouncedFilter = useDebounce((newFilter: string) => {
    setDebouncedFilter(newFilter)
  }, 300)

  return (
    <>
      {assignmentAllowedToAddLimitReached && !isSelectPanelOpen ? (
        <Tooltip
          text={`Cannot add more organizations, team has reached the ${enterpriseTeamsOrgAssignmentLimit} organization limit.`}
        >
          <Button data-testid="select-orgs-button" inactive>
            <OrganizationIcon className="mr-2" />
            Select organizations
            <TriangleDownIcon className="ml-2" />
          </Button>
        </Tooltip>
      ) : (
        <SelectPanel title="Select organizations" open={isSelectPanelOpen} onCancel={handleCancel}>
          <SelectPanel.Button
            data-testid="select-orgs-button"
            className="pr-3"
            trailingAction={TriangleDownIcon}
            onClick={() => {
              setAddingSelectedOrganizations([])
              setSelectPanelOpen(true)
            }}
          >
            <OrganizationIcon className="mr-2" />
            Select organizations
          </SelectPanel.Button>
          <SelectPanel.Header>
            {searchQueryError && (
              <Banner
                hideTitle
                title="Failed to search organizations."
                data-testid="flash-error"
                variant="critical"
                className={styles.orgSearchBanner}
              >
                Something went wrong. Please try again.
              </Banner>
            )}
            {!searchQueryError && assignmentAllowedToAddLimitReached && (
              <Banner
                hideTitle
                title={`Organization assignment limit (${enterpriseTeamsOrgAssignmentLimit}) reached.`}
                data-testid="org-assignments-limit-error"
                variant="warning"
                className={styles.orgSearchBanner}
              >
                {enterpriseTeamsOrgAssignmentLimit}-organization limit reached. Please remove some organizations before
                adding more.
              </Banner>
            )}
            <SelectPanel.SearchInput
              data-testid="org-search-input"
              placeholder="Search organizations"
              aria-label="Search organizations"
              value={filter}
              onChange={e => handleFilterChange(e.target.value)}
              className={styles.searchInput}
            />
          </SelectPanel.Header>
          {searchQueryPending || filter !== debouncedFilter ? (
            <div className={styles.orgSearchBlankState}>
              <SelectPanel.Message variant="empty" title="">
                <Spinner />
              </SelectPanel.Message>
            </div>
          ) : eligibleOrganizations.length === 0 ? (
            searchResults?.totalAvailableCount === 0 ? (
              <div className={styles.orgSearchBlankState}>
                <SelectPanel.Message variant="empty" title="No more organizations to add">
                  <span data-testid="no-orgs-remaining-text">
                    All organizations of your enterprise have been added to this team.
                  </span>
                </SelectPanel.Message>
              </div>
            ) : (
              <div className={styles.orgSearchBlankState}>
                <SelectPanel.Message variant="empty" title="No organizations found">
                  <span data-testid="no-orgs-found-text">Try a different search term</span>
                </SelectPanel.Message>
              </div>
            )
          ) : (
            <ActionList selectionVariant="multiple">
              {eligibleOrganizations.map(org => (
                <ActionList.Item
                  key={org.id}
                  data-testid={`org-${org.id}`}
                  selected={addingSelectedOrganizations.some(o => o.id === org.id)}
                  disabled={
                    assignmentAllowedToAddLimitReached && !addingSelectedOrganizations.some(o => o.id === org.id)
                  }
                  onSelect={() => {
                    if (addingSelectedOrganizations.some(o => o.id === org.id)) {
                      setAddingSelectedOrganizations(addingSelectedOrganizations.filter(o => o.id !== org.id))
                    } else {
                      setAddingSelectedOrganizations([...addingSelectedOrganizations, org])
                    }
                  }}
                >
                  <Box sx={{display: 'flex', alignItems: 'flex-start'}}>
                    <GitHubAvatar
                      square
                      src={org.avatarUrl}
                      alt={`Icon for the ${org.name} organization`}
                      className={styles.avatar}
                    />
                    <span className={styles.textBold}>{org.name}</span>
                  </Box>
                </ActionList.Item>
              ))}
            </ActionList>
          )}
          <div className={`p-3 border-top ${styles.borderTop}`}>
            <div className={`d-flex flex-justify-end`}>
              <Button variant="default" size="small" onClick={handleCancel} className={styles.orgSearchFooterButton}>
                Cancel
              </Button>
              <Button
                data-testid="add-orgs"
                variant="primary"
                size="small"
                onClick={handleAddOrganizations}
                className={`ml-2 ${styles.orgSearchFooterButton}`}
              >
                Add{' '}
                <CounterLabel scheme="secondary" className={styles.addCounterLabel}>
                  {addingSelectedOrganizations.length}
                </CounterLabel>
              </Button>
            </div>
          </div>
        </SelectPanel>
      )}
    </>
  )
}

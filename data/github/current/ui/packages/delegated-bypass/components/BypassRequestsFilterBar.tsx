import {ActionList} from '@primer/react'
import {TimeFilter} from '@github-ui/action-menu-selector/TimeFilter'
import {useMemo} from 'react'
import type {FC} from 'react'
import {useRelativeNavigation} from '../hooks/use-relative-navigation'
import type {DelegatedBypassFilter, SourceType} from '../delegated-bypass-types'
import {requestsIndexPath} from '../helpers/requests-filter'
import {orderedStatuses, requestStatuses} from '../helpers/constants'
import {UserSelector} from '@github-ui/user-selector'
import {useBypassActors} from '../hooks/use-bypass-actors'
import {ActionMenuSelector} from '@github-ui/action-menu-selector'
import {ReposSelector, simpleRepoLoader} from '@github-ui/repos-selector'
import {OrgSelector, simpleOrgLoader} from '@github-ui/org-selector'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {getRepoSuggestionsForOrg} from '../services/api'

type BypassRequestsFilterProps = {
  sourceType: SourceType
  filter: DelegatedBypassFilter
  repositories?: string[]
  organizations?: string[]
}

export const BypassRequestsFilterBar: FC<BypassRequestsFilterProps> = ({
  filter,
  sourceType,
  repositories,
  organizations,
}) => {
  const exemptionReposQuery = useFeatureFlag('exemption_repos_query')
  const {approver, requester, timePeriod, requestStatus, repository, organization} = filter
  const {navigate} = useRelativeNavigation()
  const updateFilter = (newFilter: DelegatedBypassFilter) => {
    newFilter.page = undefined // Reset to first page when filter changes
    navigate('.', requestsIndexPath({filter: newFilter}), true)
  }
  const requestersState = useBypassActors('Requester')
  const approversState = useBypassActors('Approver')

  const {resolvePath} = useRelativeNavigation()
  const queryForRepos = async (query: string) => {
    return (
      await getRepoSuggestionsForOrg(resolvePath('repo_suggestions'), {
        query,
        excludePublicRepos: false,
      })
    ).map(r => ({name: r.name}))
  }
  const namedRepos = useMemo(() => repositories?.map(r => ({name: r})) || [], [repositories])
  const namedOrgs = useMemo(() => organizations?.map(r => ({name: r})) || [], [organizations])

  return (
    <div className="d-flex flex-row flex-wrap mb-3">
      {sourceType === 'enterprise' && (
        <div className="d-flex p-1">
          <OrgSelector
            selection={organization ? {name: organization} : undefined}
            buttonText={organization ? organization : 'All organizations'}
            orgLoader={simpleOrgLoader(namedOrgs)}
            selectionVariant="single"
            selectOrg={selectedOrg => {
              if (selectedOrg?.name !== organization) {
                updateFilter({...filter, organization: selectedOrg?.name})
              }
            }}
            removeOrg={() => updateFilter({...filter, organization: undefined})}
          />
        </div>
      )}
      {sourceType === 'organization' && (
        <div className="d-flex p-1">
          <ReposSelector
            currentSelection={repository ? {name: repository} : undefined}
            repositoryLoader={exemptionReposQuery ? queryForRepos : simpleRepoLoader(namedRepos)}
            selectAllOption
            selectionVariant="single"
            onSelect={selectedRepository => {
              if (selectedRepository?.name !== repository) {
                updateFilter({...filter, repository: selectedRepository?.name})
              }
            }}
          />
        </div>
      )}
      <div className="d-flex p-1">
        <UserSelector
          defaultText="All approvers"
          usersState={approversState}
          currentUser={approver}
          onSelect={selectedUser => {
            if (selectedUser !== approver) {
              updateFilter({...filter, approver: selectedUser})
            }
          }}
          renderCustomFooter={() => (
            <ActionList.Item
              onSelect={() => {
                updateFilter({...filter, approver: undefined})
              }}
            >
              All approvers
            </ActionList.Item>
          )}
          label="Approver: "
          width="medium"
        />
      </div>
      <div className="d-flex p-1">
        <UserSelector
          defaultText="All requesters"
          usersState={requestersState}
          currentUser={requester}
          onSelect={selectedUser => {
            if (selectedUser !== requester) {
              updateFilter({...filter, requester: selectedUser})
            }
          }}
          renderCustomFooter={() => (
            <ActionList.Item
              onSelect={() => {
                updateFilter({...filter, requester: undefined})
              }}
            >
              All requesters
            </ActionList.Item>
          )}
          label="Requester: "
          width="medium"
        />
      </div>
      <div className="d-flex p-1">
        <TimeFilter
          currentTimePeriod={timePeriod || 'day'}
          onSelect={selectedTimePeriod => {
            if (selectedTimePeriod !== timePeriod) {
              updateFilter({...filter, timePeriod: selectedTimePeriod})
            }
          }}
        />
      </div>
      <div className="d-flex p-1">
        <ActionMenuSelector
          currentSelection={requestStatus || 'all'}
          orderedValues={orderedStatuses}
          displayValues={requestStatuses}
          onSelect={selectedBypassStatus => {
            if (selectedBypassStatus !== requestStatus) {
              updateFilter({...filter, requestStatus: selectedBypassStatus})
            }
          }}
        />
      </div>
    </div>
  )
}

import {useEffect, useState} from 'react'
import {Box, Heading, TextInput, FormControl, Pagination, Link} from '@primer/react'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {updateSearchParams} from '@github-ui/history'
import {Blankslate} from '@primer/react/experimental'
import {useDebounce} from '@github-ui/use-debounce'

type EnterpriseTeam = {
  isMembersManagementEnabled: boolean
  id: number
  name: string
  externalGroupCount: number
  memberCount: number
  organizationSelectionType: string
  showRoute: string
  externalGroupSyncStatus: string
}

export interface StafftoolsBusinessTeamsListPayload {
  // Update this type to reflect the data you place in payload in Rails
  totalEntries: number
  totalPages: number
  enterpriseTeams: EnterpriseTeam[]
  businessSlug: string
}

export function StafftoolsBusinessTeamsListView() {
  const payload = useRoutePayload<StafftoolsBusinessTeamsListPayload>()
  const [urlSearchParams, setUrlSearchParams] = useState(() => new URLSearchParams(''))
  const [currentPage, setCurrentPage] = useState(1)
  const [searchboxValue, setSearchboxValue] = useState('')
  const [enterpriseTeams, setEnterpriseTeams] = useState(payload.enterpriseTeams)
  const [totalPages, setTotalPages] = useState(payload.totalPages)

  useEffect(() => {
    const params = new URLSearchParams(location.search)
    setUrlSearchParams(params)
    setSearchboxValue(params.get('query') || '')
    setCurrentPage(parseInt(params.get('page') || '1'))
  }, [setUrlSearchParams, setSearchboxValue, setCurrentPage])

  const pluralize = (count: number, noun: string, suffix = 's') => `${count} ${noun}${count !== 1 ? suffix : ''}`

  const setSearchParam = (key: string, value: string) => {
    urlSearchParams.set(key, value)
    updateSearchParams(urlSearchParams)
  }

  const onPageChange: Parameters<typeof Pagination>['0']['onPageChange'] = (e, page) => {
    e.preventDefault()
    paginate(page)
  }

  const paginate = async (page: number): Promise<void> => {
    setSearchParam('page', page.toString())
    setCurrentPage(page)

    const result = await verifiedFetchJSON(
      `/stafftools/enterprises/${payload.businessSlug}/enterprise_teams?${urlSearchParams.toString()}`,
      {
        method: 'GET',
        headers: {Accept: 'application/json'},
      },
    )
    const data = await result.json()

    setEnterpriseTeams(data.enterpriseTeams)
    setTotalPages(data.totalPages)
  }

  const handleSearchChange = (value: string) => {
    setSearchboxValue(value)
    debouncedSearch(value)
  }

  const debouncedSearch = useDebounce((searchValue: string) => {
    setSearchParam('query', searchValue)
    paginate(1)
  }, 300)
  if (payload.enterpriseTeams.some((team: EnterpriseTeam) => team.isMembersManagementEnabled)) {
    return (
      <>
        <header className="Subhead">
          <Heading as="h2" className="Subhead-heading">
            Enterprise Teams ({payload.totalEntries})
          </Heading>
        </header>
        {payload.totalEntries > 0 ? (
          <>
            <Box sx={{display: 'flex', mb: 3}}>
              <FormControl>
                <FormControl.Label>Search Enterprise Teams</FormControl.Label>
                <TextInput
                  size="medium"
                  placeholder="Find a team..."
                  value={searchboxValue}
                  onChange={e => handleSearchChange(e.target.value)}
                  data-testid={`search-input`}
                />
              </FormControl>
            </Box>
            <div>
              <table
                className="site-admin-table"
                style={{border: `var(--borderColor-default)`, borderRadius: `var(--borderRadius-medium)`}}
              >
                <thead>
                  <tr>
                    <th style={{color: `var(--fgColor-default)`}}>Name</th>
                    <th style={{color: `var(--fgColor-default)`}}>Team Management Type</th>
                    <th style={{color: `var(--fgColor-default)`}}>Member Count</th>
                    <th style={{color: `var(--fgColor-default)`}}>Sync Status</th>
                  </tr>
                </thead>
                <tbody>
                  {enterpriseTeams.length > 0 ? (
                    enterpriseTeams.map((team: EnterpriseTeam) => (
                      <tr key={team.id}>
                        <td>
                          <Link href={team.showRoute} data-testid={`link-to-${team.id}`}>
                            {team.name}
                          </Link>
                        </td>
                        <td data-testid={`team-${team.id}-team-management-type`}>
                          {team.externalGroupCount ? 'IDP Group Linked' : 'Manually Managed'}
                        </td>
                        <td data-testid={`team-${team.id}-member-count`}>{pluralize(team.memberCount, 'member')}</td>
                        <td data-testid={`team-${team.id}-external-group-sync-status`}>
                          {team.externalGroupSyncStatus}
                        </td>
                      </tr>
                    ))
                  ) : (
                    <tr>
                      <td colSpan={4}>
                        <Box sx={{color: `var(--fgColor-default)`}}>
                          <Blankslate>
                            <Blankslate.Heading>We couldn&apos;t find any matching enterprise teams</Blankslate.Heading>
                            <Blankslate.Description>
                              No enterprise teams matched your search criteria. Adjust your search to view results.
                            </Blankslate.Description>
                          </Blankslate>
                        </Box>
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
            {enterpriseTeams.length > 0 && (
              <Pagination pageCount={totalPages} currentPage={currentPage} onPageChange={onPageChange} />
            )}
          </>
        ) : (
          <Box sx={{color: `var(--fgColor-default)`}}>
            <Blankslate>
              <Blankslate.Heading>No enterprise teams are in this enterprise.</Blankslate.Heading>
            </Blankslate>
          </Box>
        )}
      </>
    )
  } else {
    return (
      <>
        <header className="Subhead">
          <Heading as="h2" className="Subhead-heading">
            Enterprise Teams ({payload.totalEntries})
          </Heading>
        </header>
        {payload.totalEntries > 0 ? (
          <>
            <Box sx={{display: 'flex', mb: 3}}>
              <FormControl>
                <FormControl.Label>Search Enterprise Teams</FormControl.Label>
                <TextInput
                  size="medium"
                  placeholder="Find a team..."
                  value={searchboxValue}
                  onChange={e => handleSearchChange(e.target.value)}
                  data-testid={`search-input`}
                />
              </FormControl>
            </Box>
            <div>
              <table
                className="site-admin-table"
                style={{border: `var(--borderColor-default)`, borderRadius: `var(--borderRadius-medium)`}}
              >
                <thead>
                  <tr>
                    <th style={{color: `var(--fgColor-default)`}}>Name</th>
                    <th style={{color: `var(--fgColor-default)`}}>External Group Count</th>
                    <th style={{color: `var(--fgColor-default)`}}>Member Count</th>
                    <th style={{color: `var(--fgColor-default)`}}>Synced Org Teams</th>
                  </tr>
                </thead>
                <tbody>
                  {enterpriseTeams.length > 0 ? (
                    enterpriseTeams.map((team: EnterpriseTeam) => (
                      <tr key={team.id}>
                        <td>
                          <Link href={team.showRoute} data-testid={`link-to-${team.id}`}>
                            {team.name}
                          </Link>
                        </td>
                        <td data-testid={`team-${team.id}-external-group-count`}>
                          {pluralize(team.externalGroupCount, 'linked group')}
                        </td>
                        <td data-testid={`team-${team.id}-member-count`}>{pluralize(team.memberCount, 'member')}</td>
                        <td data-testid={`team-${team.id}-org-selection-type`}>{team.organizationSelectionType}</td>
                      </tr>
                    ))
                  ) : (
                    <tr>
                      <td colSpan={4}>
                        <Box sx={{color: `var(--fgColor-default)`}}>
                          <Blankslate>
                            <Blankslate.Heading>We couldn&apos;t find any matching enterprise teams</Blankslate.Heading>
                            <Blankslate.Description>
                              No enterprise teams matched your search criteria. Adjust your search to view results.
                            </Blankslate.Description>
                          </Blankslate>
                        </Box>
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
            {enterpriseTeams.length > 0 && (
              <Pagination pageCount={totalPages} currentPage={currentPage} onPageChange={onPageChange} />
            )}
          </>
        ) : (
          <Box sx={{color: `var(--fgColor-default)`}}>
            <Blankslate>
              <Blankslate.Heading>No enterprise teams are in this enterprise.</Blankslate.Heading>
            </Blankslate>
          </Box>
        )}
      </>
    )
  }
}

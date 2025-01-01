import {useEffect, useState} from 'react'
import {Box, Heading, TextInput, FormControl, Pagination, Link} from '@primer/react'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'

type EnterpriseTeam = {
  id: number
  name: string
  externalGroupCount: number
  memberCount: number
  organizationSelectionType: string
  showRoute: string
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
    window.history.replaceState({...window.history.state}, '', `?${urlSearchParams.toString()}`)
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
    setSearchParam('query', value)
    setSearchboxValue(value)
    paginate(1)
  }

  return (
    <>
      <header className="Subhead">
        <Heading as="h2" className="Subhead-heading">
          Enterprise Teams ({payload.totalEntries})
        </Heading>
      </header>
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
        <table className="site-admin-table">
          <thead>
            <tr>
              <th>Name</th>
              <th>External Group Count</th>
              <th>Member Count</th>
              <th>Synced Org Teams</th>
            </tr>
          </thead>

          <tbody>
            {enterpriseTeams.map((team: EnterpriseTeam) => (
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
            ))}
          </tbody>
        </table>
      </div>
      <Pagination pageCount={totalPages} currentPage={currentPage} onPageChange={onPageChange} />
    </>
  )
}

import {useEffect, useState} from 'react'
import {Box, Heading, TextInput, FormControl, Pagination, Link} from '@primer/react'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'

type EnterpriseTeam = {
  id: number
  name: string
  memberCount: number
  showRoute: string
}

type EnterpriseTeamMember = {
  id: number
  name: string
  login: string
  showRoute: string
}

export interface StafftoolsBusinessTeamMembersPayload {
  // Update this type to reflect the data you place in payload in Rails
  totalEntries: number
  totalPages: number
  enterpriseTeam: EnterpriseTeam
  members: EnterpriseTeamMember[]
  businessSlug: string
}

export function StafftoolsBusinessTeamMembersView() {
  const payload = useRoutePayload<StafftoolsBusinessTeamMembersPayload>()
  const [urlSearchParams, setUrlSearchParams] = useState(() => new URLSearchParams(''))
  const [currentPage, setCurrentPage] = useState(1)
  const [searchboxValue, setSearchboxValue] = useState('')
  const [members, setMembers] = useState(payload.members)
  const [totalPages, setTotalPages] = useState(payload.totalPages)

  useEffect(() => {
    const params = new URLSearchParams(location.search)
    setUrlSearchParams(params)
    setSearchboxValue(params.get('query') || '')
    setCurrentPage(parseInt(params.get('page') || '1'))
  }, [setUrlSearchParams, setSearchboxValue, setCurrentPage])

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
      `/stafftools/enterprises/${payload.businessSlug}/enterprise_teams/${
        payload.enterpriseTeam.id
      }/members?${urlSearchParams.toString()}`,
      {
        method: 'GET',
        headers: {Accept: 'application/json'},
      },
    )
    const data = await result.json()

    setMembers(data.members)
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
          <Link
            href={payload.enterpriseTeam.showRoute}
            data-testid={`team-link-${payload.enterpriseTeam.id}`}
            className="text-underline"
            sx={{mr: 1}}
          >
            {payload.enterpriseTeam.name}
          </Link>
          / Members ({payload.totalEntries})
        </Heading>
      </header>
      <Box sx={{display: 'flex', mb: 3}}>
        <FormControl>
          <FormControl.Label>Search members</FormControl.Label>
          <TextInput
            size="medium"
            placeholder="Find a member..."
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
              <th>Login</th>
              <th>Name</th>
            </tr>
          </thead>

          <tbody>
            {members.map((member: EnterpriseTeamMember) => (
              <tr key={member.id}>
                <td>
                  <Link href={member.showRoute} data-testid={`member-link-${member.id}`}>
                    {member.login}
                  </Link>
                </td>
                <td data-testid={`member-name-${member.id}`}>{member.name}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <Pagination pageCount={totalPages} currentPage={currentPage} onPageChange={onPageChange} />
    </>
  )
}

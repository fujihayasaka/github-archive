import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useEffect, useState} from 'react'
import {Box, Heading, TextInput, FormControl, Pagination, Link} from '@primer/react'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {updateSearchParams} from '@github-ui/history'
import {Blankslate} from '@primer/react/experimental'
import {useDebounce} from '@github-ui/use-debounce'

type Organization = {
  id: number
  name: string
  showRoute: string
}

type EnterpriseTeam = {
  id: number
  name: string
  showRoute: string
}

export interface StafftoolsBusinessTeamOrganizationsPayload {
  totalEntries: number
  totalPages: number
  enterpriseTeam: EnterpriseTeam
  orgs: Organization[]
  businessSlug: string
}

export function StafftoolsBusinessTeamOrganizationsView() {
  const payload = useRoutePayload<StafftoolsBusinessTeamOrganizationsPayload>()
  const [urlSearchParams, setUrlSearchParams] = useState(() => new URLSearchParams(''))
  const [currentPage, setCurrentPage] = useState(1)
  const [searchboxValue, setSearchboxValue] = useState('')
  const [organizations, setOrganizations] = useState(payload.orgs)
  const [totalPages, setTotalPages] = useState(payload.totalPages)

  useEffect(() => {
    const params = new URLSearchParams(location.search)
    setUrlSearchParams(params)
    setSearchboxValue(params.get('query') || '')
    setCurrentPage(parseInt(params.get('page') || '1'))
  }, [setUrlSearchParams, setSearchboxValue, setCurrentPage])

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
      `/stafftools/enterprises/${payload.businessSlug}/enterprise_teams/${
        payload.enterpriseTeam.id
      }/organizations?${urlSearchParams.toString()}`,
      {
        method: 'GET',
        headers: {Accept: 'application/json'},
      },
    )
    const data = await result.json()

    if (data && data.orgs) {
      setOrganizations(data.orgs)
      setTotalPages(data.totalPages)
    } else {
      setOrganizations([])
      setTotalPages(0)
    }
  }

  const handleSearchChange = (value: string) => {
    setSearchboxValue(value)
    debouncedSearch(value)
  }

  const debouncedSearch = useDebounce((searchValue: string) => {
    setSearchParam('query', searchValue)
    paginate(1)
  }, 300)

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
          / Organizations ({payload.totalEntries})
        </Heading>
      </header>
      {payload.totalEntries > 0 ? (
        <>
          <Box sx={{display: 'flex', mb: 3}}>
            <FormControl>
              <FormControl.Label>Search organizations</FormControl.Label>
              <TextInput
                size="medium"
                placeholder="Find an organization..."
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
                </tr>
              </thead>
              <tbody>
                {organizations.length > 0 ? (
                  organizations.map((organization: Organization) => (
                    <tr key={organization.id}>
                      <td>
                        <Link href={organization.showRoute} data-testid={`org-link-${organization.id}`}>
                          {organization.name}
                        </Link>
                      </td>
                    </tr>
                  ))
                ) : (
                  <tr>
                    <td colSpan={1}>
                      <Box sx={{color: `var(--fgColor-default)`}}>
                        <Blankslate>
                          <Blankslate.Heading>We couldn&apos;t find any matching organizations</Blankslate.Heading>
                          <Blankslate.Description>
                            No organizations matched your search criteria. Adjust your search to view results.
                          </Blankslate.Description>
                        </Blankslate>
                      </Box>
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
          {organizations.length > 0 && (
            <Pagination pageCount={totalPages} currentPage={currentPage} onPageChange={onPageChange} />
          )}
        </>
      ) : (
        <Box sx={{color: `var(--fgColor-default)`}}>
          <Blankslate>
            <Blankslate.Heading>No organizations are assigned to this enterprise team.</Blankslate.Heading>
          </Blankslate>
        </Box>
      )}
    </>
  )
}

import {useReplaceSearchParams} from '../hooks/UseReplaceSearchParams'
import {useState} from 'react'
import {TextInput, Link} from '@primer/react'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {SearchIcon} from '@primer/octicons-react'
import {DataTable, Table, Blankslate} from '@primer/react/experimental'
import type {FilterOptionProps} from '../components/FilterOption'
import type {Column} from '@primer/react/experimental'
import {SortButton} from '../components/SortButton'
import {FilterOption} from '../components/FilterOption'
import {InstallationAvatar} from '../components/InstallationAvatar'

export interface RequestsTableProps {
  title: string
  description: string
  filters?: FilterOptionProps[]
  rows: RequestTableRow[]
  page_size: number
  total_count: number
  variant?: string
  placeholder_text?: string
  pagination_text?: string
}

export interface RequestTableRow {
  id: number
  http_method?: string
  name: string
  total_requests: string
  rate_limited_requests: string
  last_rate_limited: string
  description: string
  href?: string
  icon_url?: string
  installation_icon?: boolean
  icon_background_color?: string
  square_icon?: boolean
}

type CustomRowFunction = (row: RequestTableRow) => JSX.Element
type HttpMethodFunction = () => Column<RequestTableRow>

const requestsCustomRow: CustomRowFunction = row => {
  const installation_icon = row?.installation_icon || false
  const square_icon = row?.square_icon || false
  return (
    <div className="d-flex flex-row flex-items-center gap-2">
      {row.icon_url && !installation_icon && <GitHubAvatar src={row.icon_url} size={32} square={square_icon} />}
      {row.icon_url && installation_icon && (
        <InstallationAvatar icon_url={row.icon_url} icon_background_color={row?.icon_background_color} />
      )}
      <div className="d-flex flex-column">
        <Link href={row.href || '#'} className="f5 text-bold fgColor-default">
          {row.name}
        </Link>
        <span className="f6 fgColor-muted text-normal">{row.description}</span>
      </div>
    </div>
  )
}
const routesCustomRow: CustomRowFunction = row => {
  return (
    <div className="d-flex flex-column">
      <span className="f5 text-bold fgColor-default">{row.name}</span>
      <span className="f6 fgColor-muted text-normal">{row.description}</span>
    </div>
  )
}

const httpMethodColumn: HttpMethodFunction = () => {
  return {
    header: () => {
      return <SortButton title="Method" query_param="m" clear_query_params={['n', 'tr', 'rlr', 'lrl']} />
    },
    rowHeader: true,
    field: 'http_method',
    renderCell: (row: RequestTableRow) => {
      return <span className="f5 text-normal">{row.http_method}</span>
    },
  }
}

type Variants = {
  [key: string]: {row: CustomRowFunction; name: string; http_method: boolean}
}
const variants: Variants = {
  requests: {row: requestsCustomRow, name: 'Name', http_method: false},
  routes: {row: routesCustomRow, name: 'Route', http_method: true},
}

export function RequestsTable({
  variant = 'requests',
  title,
  description,
  filters,
  rows,
  page_size,
  total_count,
  placeholder_text,
  pagination_text,
}: RequestsTableProps) {
  const {searchParams, replaceSearchParam} = useReplaceSearchParams()
  const [value, setValue] = useState(searchParams.get('q') || '')
  const currentPage = parseInt(searchParams.get('p') || '1', 10) - 1
  const handleChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    setValue(event.target.value)
  }
  const showBlankslate = rows.length === 0

  return (
    <div className="d-flex flex-column gap-3 mt-3">
      <div className="d-flex flex-column">
        <h3 className="h4 m-0">{title}</h3>
        <p className="m-0 fgColor-muted">{description}</p>
      </div>
      <div className="d-flex flex-column flex-lg-row gap-2">
        <TextInput
          aria-label={placeholder_text || 'Search'}
          placeholder={placeholder_text || 'Search'}
          className="flex-1"
          onKeyDown={event => {
            // This is not a hotkey, submits the search input
            // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
            if (event.key === 'Enter') {
              replaceSearchParam('q', value)
            }
          }}
          trailingAction={
            <TextInput.Action
              onClick={() => {
                replaceSearchParam('q', value)
              }}
              icon={SearchIcon}
              aria-label="Search"
              className="rounded-0 borderColor-default border-0 border-left"
            />
          }
          value={value}
          onChange={handleChange}
        />
        {filters &&
          filters.map(filter => {
            return <FilterOption key={filter.group.query_param} {...filter} />
          })}
      </div>
      {showBlankslate && (
        <Blankslate border>
          <Blankslate.Heading>No results found</Blankslate.Heading>
          <Blankslate.Description>
            Try a different time period or other filters. Visit the API insights documentation to learn more.
          </Blankslate.Description>
          <Blankslate.PrimaryAction href="https://github.co/api-insights-docs">
            Get started with API insights
          </Blankslate.PrimaryAction>
        </Blankslate>
      )}
      {!showBlankslate && (
        <Table.Container>
          <DataTable
            aria-labelledby="actors"
            aria-describedby="actors-subtitle"
            data={rows}
            columns={[
              ...(variants[variant]?.http_method ? [httpMethodColumn()] : []),
              {
                header: () => {
                  return (
                    <SortButton
                      title={variants[variant]?.name || 'Name'}
                      query_param="n"
                      clear_query_params={['tr', 'rlr', 'lrl', 'm']}
                    />
                  )
                },
                rowHeader: true,
                field: 'name',
                renderCell: variants[variant]?.row,
              },
              {
                header: () => {
                  return (
                    <SortButton
                      title="Total REST requests"
                      query_param="tr"
                      clear_query_params={['n', 'rlr', 'lrl', 'm']}
                    />
                  )
                },
                field: 'total_requests',
                renderCell: row => {
                  return <span className="f5 px-1">{row.total_requests}</span>
                },
              },
              {
                header: () => {
                  return (
                    <SortButton
                      title="Primary-rate-limited requests"
                      query_param="rlr"
                      clear_query_params={['tr', 'n', 'lrl', 'm']}
                    />
                  )
                },
                field: 'rate_limited_requests',
                renderCell: row => {
                  return <span className="f5 px-1">{row.rate_limited_requests}</span>
                },
              },
              {
                header: () => {
                  return (
                    <SortButton
                      title="Last primary-rate-limited"
                      query_param="lrl"
                      clear_query_params={['tr', 'rlr', 'n', 'm']}
                    />
                  )
                },
                field: 'last_rate_limited',
                renderCell: row => {
                  return <span className="f5 px-1">{row.last_rate_limited}</span>
                },
              },
            ]}
          />
          <Table.Pagination
            aria-label={pagination_text || 'Pagination'}
            pageSize={page_size}
            totalCount={total_count}
            defaultPageIndex={currentPage}
            onChange={({pageIndex}) => {
              replaceSearchParam('p', (pageIndex + 1).toString())
            }}
          />
        </Table.Container>
      )}
    </div>
  )
}

import DataCard from '@github-ui/data-card'
import {addUrlToHistoryStack} from '@github-ui/history'
import {AlertIcon, ShieldCheckIcon} from '@primer/octicons-react'
import {Link} from '@primer/react'
import {Blankslate, type Column, DataTable, Table} from '@primer/react/experimental'
import {useEffect, useMemo, useState} from 'react'
import {useSearchParams} from 'react-router-dom'

import {CursorPagination} from '../../../common/components/cursor-pagination'
import styles from './RepositoriesTable.module.css'
import SortHeader, {type Sort, type SortDirection} from './SortHeader'
import useRepositoriesQuery, {type RepositoryRow} from './use-repositories-query'

const DEFAULT_SORT: Sort<RepositoryRow> = {field: 'countOpen', direction: 'desc'}

const numberFormatter = Intl.NumberFormat('en-US', {notation: 'standard'})

interface RepositoriesTableProps {
  query: string
}

export default function RepositoriesTable(props: RepositoriesTableProps): JSX.Element {
  const [searchParams] = useSearchParams()

  // track paging cursor
  const [cursor, setCursor] = useState<string | undefined>()

  // track table sorting
  const [sort, setSort] = useState<Sort<RepositoryRow>>(() => {
    const field = searchParams.get('repos[sortField]')
    const direction = searchParams.get('repos[sortDir]')
    if (field && direction) {
      return {
        field: field as keyof RepositoryRow,
        direction: direction as SortDirection,
      }
    }
    return DEFAULT_SORT
  })

  // reset page cursor whenever filter or sorting changes
  useEffect(() => setCursor(undefined), [props, sort])

  // keep browser URL in sync with selected sort field/direction
  useEffect(() => {
    const url = new URL(window.location.href, window.location.origin)
    const nextParams = url.searchParams

    if (sort.field === DEFAULT_SORT.field && sort.direction === DEFAULT_SORT.direction) {
      nextParams.delete('repos[sortField]')
      nextParams.delete('repos[sortDir]')
    } else {
      nextParams.set('repos[sortField]', sort.field)
      nextParams.set('repos[sortDir]', sort.direction)
    }

    addUrlToHistoryStack(`${url.pathname}${url.search}`)
  }, [sort])

  const dataQuery = useRepositoriesQuery({...props, cursor, sort})

  const columns: Array<Column<RepositoryRow>> = useMemo(() => {
    return [
      {
        header: 'Repository',
        field: 'displayName',
        renderCell: row => (
          <Link href={row.href} className={styles.Link}>
            {row.displayName}
          </Link>
        ),
      },
      {
        header: (): JSX.Element => (
          <SortHeader field="countOpen" sort={sort} onSortChange={setSort}>
            Open alerts
          </SortHeader>
        ),
        field: 'countOpen',
        align: 'end',
        renderCell: (row: RepositoryRow) => numberFormatter.format(row.countOpen),
      },
      {
        header: (): JSX.Element => (
          <SortHeader field="countEPSS" sort={sort} onSortChange={setSort}>
            EPSS &gt; 1%
          </SortHeader>
        ),
        field: 'countEPSS',
        align: 'end',
        renderCell: (row: RepositoryRow) => numberFormatter.format(row.countEPSS),
      },
      {
        header: (): JSX.Element => (
          <SortHeader field="countCritical" sort={sort} onSortChange={setSort}>
            Critical
          </SortHeader>
        ),
        field: 'countCritical',
        align: 'end',
        renderCell: (row: RepositoryRow) => numberFormatter.format(row.countCritical),
      },
      {
        header: (): JSX.Element => (
          <SortHeader field="countHigh" sort={sort} onSortChange={setSort}>
            High
          </SortHeader>
        ),
        field: 'countHigh',
        align: 'end',
        renderCell: (row: RepositoryRow) => numberFormatter.format(row.countHigh),
      },
      {
        header: (): JSX.Element => (
          <SortHeader field="countMedium" sort={sort} onSortChange={setSort}>
            Medium
          </SortHeader>
        ),
        field: 'countMedium',
        align: 'end',
        renderCell: (row: RepositoryRow) => numberFormatter.format(row.countMedium),
      },
      {
        header: (): JSX.Element => (
          <SortHeader field="countLow" sort={sort} onSortChange={setSort}>
            Low
          </SortHeader>
        ),
        field: 'countLow',
        align: 'end',
        renderCell: (row: RepositoryRow) => numberFormatter.format(row.countLow),
      },
    ]
  }, [sort])

  const blankslateParentStyle = useMemo(
    () => ({
      display: 'flex',
      flexDirection: 'column',
      height: 366,
      width: '100%',
      justifyContent: 'center',
    }),
    [],
  )

  if (dataQuery.isPending) {
    return (
      <Table.Container>
        <Table.Skeleton data-testid="loading-indicator" columns={columns} rows={10} />
      </Table.Container>
    )
  }

  if (dataQuery.isError) {
    return (
      <DataCard sx={blankslateParentStyle} data-testid="error-indicator">
        <Blankslate>
          <Blankslate.Visual>
            <AlertIcon size="medium" />
          </Blankslate.Visual>
          <Blankslate.Description>Repository information could not be loaded right now</Blankslate.Description>
        </Blankslate>
      </DataCard>
    )
  }

  if (dataQuery.data.items.length === 0) {
    return (
      <DataCard sx={blankslateParentStyle} data-testid="empty-indicator">
        <Blankslate>
          <Blankslate.Visual>
            <ShieldCheckIcon size="medium" />
          </Blankslate.Visual>
          <Blankslate.Description>
            Try modifying your filters to see the security impact on your organization.
          </Blankslate.Description>
        </Blankslate>
      </DataCard>
    )
  }

  return (
    <Table.Container>
      <Table.Title id="repos-table-title">
        <span className="sr-only">Repositories</span>
      </Table.Title>
      <Table.Subtitle id="repos-table-subtitle">
        <span className="sr-only">
          A listing of repositories with counts of alerts found during pull requests, and how those alerts were handled
          before pull request merge.
        </span>
      </Table.Subtitle>
      {/* DataTable has a default margin top when used with a Title/Subtitle. Since we're
        only including the title/subtitle for aria (sr-only), we don't need this margin.
        Including an empty element here breaks the CSS rule so that we get the styling we want. */}
      <span />
      <DataTable
        aria-labelledby="repos-table-title"
        aria-describedby="repos-table-subtitle"
        columns={columns}
        data={dataQuery.data?.items}
      />
      <div className={styles.Box}>
        <CursorPagination
          previousCursor={dataQuery.data.previous}
          nextCursor={dataQuery.data.next}
          onPageChange={setCursor}
        />
      </div>
    </Table.Container>
  )
}

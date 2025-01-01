import {Blankslate, DataTable, Stack, Table, type Column} from '@primer/react/experimental'
import type {DashboardIssue} from '../data-types'
import {Link} from '@github-ui/react-core/link'

const columns: Array<Column<DashboardIssue>> = [
  {
    header: 'Title',
    field: 'title',
    renderCell: ({url, title}) => {
      return <Link to={url}>{title}</Link>
    },
  },
  {
    header: 'State',
    field: 'state',
  },
]

export function IssueTable({issues, isPending}: {issues: DashboardIssue[]; isPending: boolean}) {
  return (
    <Stack>
      {!isPending && issues.length === 0 ? (
        <Blankslate>No issues to display</Blankslate>
      ) : (
        <Table.Container>
          {isPending ? <Table.Skeleton rows={10} columns={columns} /> : <DataTable data={issues} columns={columns} />}
        </Table.Container>
      )}
    </Stack>
  )
}

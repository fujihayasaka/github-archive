import {Link} from '@github-ui/react-core/link'
import {Blankslate, type Column, DataTable, Stack, Table} from '@primer/react/experimental'
import {useEffect, useState} from 'react'

import type {Issue} from '../data-types'

const columns: Array<Column<Issue>> = [
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

export function IssueTable({
  issues,
  isPending,
  isError,
  onRetry,
}: {
  issues: Issue[]
  isPending?: boolean
  isError?: boolean
  onRetry?: () => void
}) {
  const [isDismissed, setIsDismissed] = useState(false)
  // Reset dismissal state so we can show the error dialog again there's a new error
  useEffect(() => {
    if (!isError) {
      setIsDismissed(false)
    }
  }, [isError])

  return (
    <Stack data-testid="issue-table">
      {!isPending && !isError && issues.length === 0 ? (
        <Blankslate>No items to display</Blankslate>
      ) : (
        <Table.Container>
          {isPending || isError ? (
            <Table.Skeleton aria-label="Loading Issues" rows={10} columns={columns} />
          ) : (
            <DataTable aria-label="Issues" data={issues} columns={columns} />
          )}
          {isError && !isDismissed ? (
            <Table.ErrorDialog
              onDismiss={() => {
                setIsDismissed(true)
              }}
              onRetry={() => {
                onRetry?.()
              }}
            >
              There was a problem loading items
            </Table.ErrorDialog>
          ) : null}
        </Table.Container>
      )}
    </Stack>
  )
}

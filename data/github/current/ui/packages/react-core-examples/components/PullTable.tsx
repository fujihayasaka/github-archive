import {Link} from '@github-ui/react-core/link'
import {AlertIcon} from '@primer/octicons-react'
import {IssueLabelToken, Spinner} from '@primer/react'
import {Blankslate, type Column, DataTable, SkeletonText, Stack, Table} from '@primer/react/experimental'
import {useEffect, useMemo, useState} from 'react'

import type {Pull} from '../data-types'

const getColumns = (isDeferredPending?: boolean, isDeferredError?: boolean): Array<Column<Pull>> => {
  return [
    {
      header: 'Title',
      field: 'title',
      renderCell: ({url, title}: Pull) => {
        return <Link to={url}>{title}</Link>
      },
    },
    {
      header: 'State',
      field: 'state',
    },
    {
      header: () => (
        <Stack direction="horizontal" gap="condensed" align="center">
          <span>Labels</span>
          {isDeferredPending && <Spinner size="small" />}
          {isDeferredError && <AlertIcon />}
        </Stack>
      ),
      field: 'labels',
      renderCell: ({labels}: Pull) => {
        if (isDeferredPending && !isDeferredError) {
          return <SkeletonText />
        } else {
          return (
            <Stack direction="horizontal" gap="condensed">
              {labels?.map(label => <IssueLabelToken key={label.id} text={label.name} fillColor={`#${label.color}`} />)}
            </Stack>
          )
        }
      },
    },
  ]
}

export function PullTable({
  pulls,
  isPending,
  isError,
  isDeferredPending,
  isDeferredError,
  onRetry,
}: {
  pulls: Pull[]
  isPending?: boolean
  isError?: boolean
  isDeferredPending: boolean
  isDeferredError: boolean
  onRetry?: () => void
}) {
  const [isDismissed, setIsDismissed] = useState(false)
  // Reset dismissal state so we can show the error dialog again there's a new error
  useEffect(() => {
    if (!isError) {
      setIsDismissed(false)
    }
  }, [isError])

  const columns = useMemo(() => {
    return getColumns(isDeferredPending, isDeferredError)
  }, [isDeferredPending, isDeferredError])

  return (
    <Stack data-testid="pull-table">
      {!isPending && !isError && pulls.length === 0 ? (
        <Blankslate>No items to display</Blankslate>
      ) : (
        <Table.Container>
          {isPending || isError ? (
            <Table.Skeleton aria-label="Loading Pulls" rows={10} columns={columns} />
          ) : (
            <DataTable aria-label="Pulls" data={pulls} columns={columns} />
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

import {ActionMenu, ActionList, type BetterSystemStyleObject} from '@primer/react'

import type {SortName} from '../../types'
import {SortAscIcon, SortDescIcon} from '@primer/octicons-react'
import {useCallback, useEffect, useMemo, useState} from 'react'

type Props = {
  sort: (sortName: SortName) => void
  sortDetails: SortName
  sortOptions?: Partial<Record<SortName, string>>
  cancellation?: boolean
  display_activity?: boolean
}

const getSortIcon = (sort: SortName) => {
  if (sort.includes('asc')) {
    return SortAscIcon
  }

  return SortDescIcon
}

const sortTypeText: Record<SortName, string> = {
  name_asc: 'Name ascending',
  name_desc: 'Name descending',
  use_asc: 'Last active date ascending',
  use_desc: 'Last active date descending',
  requested_at_asc: 'Request date ascending',
  requested_at_desc: 'Request date descending',
  pending_cancelled_asc: 'Cancelled first',
  pending_cancelled_desc: 'Cancelled last',
  member_count_asc: 'Member count ascending',
  member_count_desc: 'Member count descending',
}

export function MemberSort(props: Props) {
  const {
    sort,
    sortDetails,
    // eslint-disable-next-line @eslint-react/no-unstable-default-props
    sortOptions = {
      name_asc: 'Name ascending (A…Z)',
      name_desc: 'Name descending (Z…A)',
      ...(props.display_activity && {
        use_asc: 'Last active date (Oldest first)',
        use_desc: 'Last active date (Newest first)',
      }),
      ...(props.cancellation && {pending_cancelled_asc: 'Cancelled first', pending_cancelled_desc: 'Cancelled last'}),
    },
    cancellation,
  } = props
  const [didSort, setDidSort] = useState(sortDetails === 'pending_cancelled_asc')

  useEffect(() => {
    if (!cancellation && sortDetails === 'pending_cancelled_asc') {
      setDidSort(false)
    }
  }, [cancellation, sortDetails])

  const doSort = useCallback(
    (sortName: SortName) => {
      setDidSort(true)
      sort(sortName)
    },
    [sort],
  )

  const sortOptionComponents = useMemo(() => {
    return Object.entries(sortOptions).map(([sortName, sortLabel], index) => {
      let sx = {}
      if (index === 0) {
        sx = {
          '&:before': {
            content: ' ',
            display: 'block',
            position: 'absolute',
            width: '100%',
            top: '-7px',
            borderWidth: '1px 0px 0px',
            borderStyle: 'solid',
            borderImage: 'initial',
            borderColor: 'var(--divider-color,transparent)',
          },
        }
      }

      return (
        <SortOption
          label={sortLabel}
          sort={sortName as SortName}
          sortDetails={sortDetails}
          doSort={doSort}
          sx={sx}
          key={sortName}
        />
      )
    })
  }, [doSort, sortDetails, sortOptions])

  return (
    <ActionMenu>
      <ActionMenu.Button
        size="small"
        sx={{border: 0, boxShadow: 'none', color: 'fg.muted', mr: 1}}
        leadingVisual={getSortIcon(sortDetails)}
      >
        {didSort ? sortTypeText[sortDetails] : 'Sort'}
      </ActionMenu.Button>
      <ActionMenu.Overlay width="medium">
        <ActionList selectionVariant="single" showDividers>
          {sortOptionComponents.map(option => option)}
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}

const SortOption = (props: {
  label: string
  sort: SortName
  sortDetails: SortName
  doSort: (sortName: SortName) => void
  sx?: BetterSystemStyleObject
}) => {
  const {label, sort, sortDetails, doSort, sx} = props

  return (
    <ActionList.Item selected={sortDetails === sort} onSelect={() => doSort(sort)} sx={sx}>
      {label}
    </ActionList.Item>
  )
}

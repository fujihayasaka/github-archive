import {useMemo} from 'react'
import {useRangeSelection, type RangeSelectionContextValues} from '../contexts/RangeSelectionContext'
import {ActionMenu, ActionList} from '@primer/react'

type Range = Pick<RangeSelectionContextValues, 'from' | 'to'>
type TimePeriod = Range & {
  from: number
  name: string
}

const timePeriods: TimePeriod[] = [
  {
    name: 'All',
    from: 0,
  },
  {
    name: 'Last month',
    from: getPreviousSaturday({periodType: 'month', offset: 1}),
  },
  {
    name: 'Last 3 months',
    from: getPreviousSaturday({periodType: 'month', offset: 3}),
  },
  {
    name: 'Last 6 months',
    from: getPreviousSaturday({periodType: 'month', offset: 6}),
  },
  {
    name: 'Last 12 months',
    from: getPreviousSaturday({periodType: 'month', offset: 12}),
  },
  {
    name: 'Last 24 months',
    from: getPreviousSaturday({periodType: 'month', offset: 24}),
  },
]

type getPreviousSaturdayProps = {
  periodType: 'week' | 'month'
  offset: number
}
function getPreviousSaturday(props?: getPreviousSaturdayProps): number {
  const date = new Date()
  date.setHours(0, 0, 0, 0)
  if (props?.periodType === 'week') {
    date.setDate(date.getDate() - props.offset * 7)
  } else if (props?.periodType === 'month') {
    date.setMonth(date.getMonth() - props.offset)
  }
  date.setDate(date.getDate() - ((date.getDay() + 1) % 7))
  return date.getTime()
}

type RangePickerProps = {
  minDate?: number
}
export function RangePicker({minDate = 0}: RangePickerProps) {
  const rangeSelection = useRangeSelection()
  const selectedTimePeriod = useMemo<TimePeriod | undefined>(() => {
    if (!rangeSelection.from) {
      return timePeriods[0]
    }
    if (rangeSelection.to) {
      return undefined
    }
    return timePeriods.find(({from}) => from === rangeSelection.from)
  }, [rangeSelection])

  const validTimePeriods = useMemo(() => {
    const index = timePeriods.slice(1).findIndex(({from}) => from <= minDate)
    if (index === -1) {
      return timePeriods
    }
    return timePeriods.slice(0, index + 2)
  }, [minDate])

  return (
    <ActionMenu>
      <ActionMenu.Button>
        <span className="text-bold">Period</span>: {selectedTimePeriod?.name || 'Custom range'}
      </ActionMenu.Button>
      <ActionMenu.Overlay width="auto">
        <ActionList selectionVariant="single">
          {validTimePeriods.map(({name, from}) => (
            <ActionList.Item
              key={name}
              onSelect={() => {
                if (name === 'All') {
                  rangeSelection.setDate({})
                } else {
                  rangeSelection.setDate({from})
                }
              }}
              selected={(name === 'All' && !rangeSelection.from) || rangeSelection.from === from}
            >
              {name}
            </ActionList.Item>
          ))}
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}

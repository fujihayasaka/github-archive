import {useMemo} from 'react'
import type {OptionalRangeSelection} from '../repos-contributors-chart-types'
import {ActionMenu, ActionList} from '@primer/react'

type TimePeriod = {
  name: string
} & OptionalRangeSelection

const timePeriods: TimePeriod[] = [
  {
    name: 'All',
    from: new Date(0),
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
function getPreviousSaturday(props?: getPreviousSaturdayProps) {
  const date = new Date()
  date.setHours(0, 0, 0, 0)
  if (props?.periodType === 'week') {
    date.setDate(date.getDate() - props.offset * 7)
  } else if (props?.periodType === 'month') {
    date.setMonth(date.getMonth() - props.offset)
  }
  date.setDate(date.getDate() - ((date.getDay() + 1) % 7))
  return date
}

type RangePickerProps = {
  value?: OptionalRangeSelection
  minDate?: Date
  onChange: (rangeSelection?: OptionalRangeSelection) => void
}
// eslint-disable-next-line @eslint-react/no-unstable-default-props
export function RangePicker({value, minDate = new Date(0), onChange}: RangePickerProps) {
  const selectedTimePeriod = useMemo<TimePeriod | undefined>(() => {
    if (!value) {
      return timePeriods[0]
    }
    if (value.to) {
      return undefined
    }
    return timePeriods.find(({from}) => from.getTime() === value?.from.getTime())
  }, [value])

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
                  onChange()
                } else {
                  onChange({from})
                }
              }}
              selected={(name === 'All' && !value) || value?.from.getTime() === from.getTime()}
            >
              {name}
            </ActionList.Item>
          ))}
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}

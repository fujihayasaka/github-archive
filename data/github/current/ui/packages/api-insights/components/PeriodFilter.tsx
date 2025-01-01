import {ActionMenu, ActionList, TextInput} from '@primer/react'
import {useReplaceSearchParams} from '../hooks/UseReplaceSearchParams'
import {Dialog} from '@primer/react/experimental'
import {DatePicker} from '@github-ui/date-picker'
import {useState} from 'react'

import type {Groups} from '../types/filter-types'
import type {RangeSelection} from '@github-ui/date-picker'

export interface PeriodFilterProps {
  name: string
  groups: Groups
  period_in_seconds: number
  time_zone: string
  max_range_in_seconds: number
}

function getTime(date: Date) {
  return `${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}`
}

export function combineDateAndTime(date: Date, time: string, is_utc: boolean) {
  const [h, m] = time.split(':')
  const hours = parseInt(h || '00', 10)
  const minutes = parseInt(m || '00', 10)
  const newDate = new Date(date)

  newDate.setHours(hours)
  newDate.setMinutes(minutes)
  if (is_utc) {
    // The date and time picker are always displayed in the local timezone, adjust so we get the correct UTC date
    return new Date(
      Date.UTC(newDate.getFullYear(), newDate.getMonth(), newDate.getDate(), newDate.getHours(), newDate.getMinutes()),
    )
  }
  return newDate
}

export function shiftDate(date: Date, is_utc: boolean) {
  if (!is_utc) {
    return date
  }
  // The date and time picker are always displayed in the local timezone, adjust so UTC hours/minutes match
  const minutesOffset = date.getTimezoneOffset()
  return new Date(date.getTime() + minutesOffset * 60000)
}

export function getDateFromSearch(
  searchParams: URLSearchParams,
  query_parameter: string,
  is_utc: boolean,
  now: Date = new Date(),
  fallback_seconds: number = 0,
) {
  const timeParam = searchParams.get(query_parameter)
  const fallback = new Date(now.getTime() - fallback_seconds * 1000)
  const d = timeParam ? new Date(timeParam) : fallback
  return shiftDate(d, is_utc)
}

function getSelectedItem(groups: Groups) {
  if (groups.length <= 0) {
    return null
  }
  const group = groups[0]
  if (!group) {
    return null
  }
  return group.options.find(option => option.value === group.selected_value)
}

export function PeriodFilter({name, groups, period_in_seconds, time_zone, max_range_in_seconds}: PeriodFilterProps) {
  const {searchParams, replaceSearchParam, replaceSearchParams} = useReplaceSearchParams()

  // dialog open state
  const [isOpen, setIsOpen] = useState(false)

  const now = new Date()
  const is_utc = searchParams.get('t') !== 'local'

  const start = getDateFromSearch(searchParams, 'from', is_utc, now, period_in_seconds)
  const end = getDateFromSearch(searchParams, 'to', is_utc, now)

  const initialRange = {
    from: start,
    to: end,
  }
  const [range, setRange] = useState<RangeSelection>(initialRange)
  const [startTime, setStartTime] = useState<string>(() => getTime(start))
  const [endTime, setEndTime] = useState<string>(() => getTime(end))

  const selectedItem = getSelectedItem(groups)
  if (!selectedItem) {
    return null
  }

  return (
    <>
      {isOpen && (
        <Dialog
          title={`Custom date range (${time_zone})`}
          position="right"
          width="medium"
          onClose={() => {
            setIsOpen(false)
          }}
          footerButtons={[
            {
              buttonType: 'default',
              content: 'Reset',
              onClick: () => {
                setRange(initialRange)
                setStartTime(getTime(start))
                setEndTime(getTime(end))
              },
            },
            {
              buttonType: 'primary',
              content: 'Apply',
              onClick: () => {
                const from = combineDateAndTime(range.from, startTime, is_utc)
                const to = combineDateAndTime(range.to, endTime, is_utc)
                replaceSearchParams({from: from.toISOString(), to: to.toISOString(), period: 'custom'})
                setIsOpen(false)
              },
            },
          ]}
        >
          <div className="d-flex flex-column gap-2">
            <DatePicker
              variant="range"
              showTodayButton={false}
              dateFormat="long"
              maxDate={shiftDate(now, is_utc)}
              minDate={shiftDate(new Date(now.getTime() - max_range_in_seconds * 1000), is_utc)}
              onChange={selection => {
                if (selection) {
                  setRange(selection)
                }
              }}
              value={range}
              placeholder="Choose dates"
            />
            <div className="d-flex flex-row gap-2">
              <TextInput
                className="flex-1"
                type="time"
                value={startTime}
                onChange={event => {
                  setStartTime(event.target.value)
                }}
              />
              <TextInput
                className="flex-1"
                type="time"
                value={endTime}
                onChange={event => {
                  setEndTime(event.target.value)
                }}
              />
            </div>
          </div>
        </Dialog>
      )}
      <ActionMenu>
        <ActionMenu.Button>
          <span className="fgColor-muted">
            {name}
            {selectedItem && ': '}
          </span>
          {selectedItem && <span>{selectedItem.name}</span>}
        </ActionMenu.Button>
        <ActionMenu.Overlay width="auto">
          <ActionList selectionVariant="multiple">
            {groups.map((group, index) => (
              <ActionList.Group key={group.query_param}>
                {group.name && <ActionList.GroupHeading>{group.name}</ActionList.GroupHeading>}
                {group.options.map(option => {
                  return (
                    <ActionList.Item
                      key={option.name}
                      selected={group.selected_value === option.value}
                      disabled={option.disabled}
                      onSelect={() => {
                        if (option.is_custom) {
                          setRange(initialRange)
                          setStartTime(getTime(start))
                          setEndTime(getTime(end))
                          setIsOpen(true)
                          return
                        }
                        if (group.query_param === 'period') {
                          replaceSearchParams({from: '', to: '', [group.query_param]: option.value})
                        } else {
                          replaceSearchParam(group.query_param, option.value)
                        }
                      }}
                    >
                      {option.is_custom ? 'Custom' : option.name}
                    </ActionList.Item>
                  )
                })}
                {index + 1 < groups.length && <ActionList.Divider />}
              </ActionList.Group>
            ))}
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
    </>
  )
}

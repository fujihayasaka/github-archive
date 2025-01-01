import {DatePicker, type RangeSelection} from '@github-ui/date-picker'
import {testIdProps} from '@github-ui/test-id-props'
import {CalendarIcon, ChevronDownIcon} from '@primer/octicons-react'
import {Button} from '@primer/react'
import {clsx} from 'clsx'
import {formatISO, isValid, parseISO} from 'date-fns'
import {useCallback, useMemo} from 'react'

import {END_DATE_PARAM, PERIOD_PARAM, START_DATE_PARAM} from '../../../../platform/url'
import {useSearchParams} from '../../../../router'
import styles from './insight-custom-date-picker.module.css'

interface InsightCustomDatePickerProps {
  startDate?: string
  endDate?: string
}

export const InsightCustomDatePicker: React.FC<InsightCustomDatePickerProps> = ({startDate, endDate}) => {
  const [params, setSearchParams] = useSearchParams()

  const value = useMemo(() => {
    const from = parseISO(startDate ?? '')
    const to = parseISO(endDate ?? '')
    if (!isValid(from) || !isValid(to)) return null
    return {from, to}
  }, [endDate, startDate])

  const onChange = useCallback(
    (range: RangeSelection | null) => {
      if (!range) return
      const nextParams = new URLSearchParams(params)
      nextParams.set(PERIOD_PARAM, 'custom')
      nextParams.set(START_DATE_PARAM, formatISO(range.from, {representation: 'date'}))
      nextParams.set(END_DATE_PARAM, formatISO(range.to, {representation: 'date'}))

      setSearchParams(nextParams)
    },
    [setSearchParams, params],
  )

  const active = value !== null

  return (
    <DatePicker
      variant="range"
      value={value}
      onChange={onChange}
      placeholder="Custom range"
      anchor={({children, ...props}) => (
        <Button
          variant="invisible"
          className={clsx(styles.Trigger, active && styles.Active)}
          {...testIdProps('insight-custom-date-picker')}
          {...props}
        >
          <CalendarIcon />
          <span className={styles.TriggerLabel}>{children}</span>
          <ChevronDownIcon />
        </Button>
      )}
    />
  )
}

import {announce} from '@github-ui/aria-live'
import {clsx} from 'clsx'
import {useCallback, useMemo} from 'react'
import {type To, useLocation} from 'react-router-dom'

import type {MemexChartTimePeriod} from '../../../../api/charts/contracts/api'
import {END_DATE_PARAM, PERIOD_PARAM, START_DATE_PARAM} from '../../../../platform/url'
import {Link} from '../../../../router'
import {InsightsResources} from '../../../../strings'
import styles from './period-navigation.module.css'

interface PeriodOption {
  value: MemexChartTimePeriod
  text?: string
  ariaLabel?: string
}

const PERIOD_OPTIONS: Array<PeriodOption> = [
  {value: '2W', ariaLabel: 'Last 2 weeks'},
  {value: '1M', ariaLabel: 'Last month'},
  {value: '3M', ariaLabel: 'Last 3 months'},
  {text: 'Max', value: 'max'},
]

function PeriodNavigationLink({
  periodValue,
  selected,
  children,
  'aria-label': ariaLabel,
}: {
  periodValue: MemexChartTimePeriod
  selected: boolean
  children: string
  'aria-label'?: string
}) {
  const location = useLocation()

  const to: To = useMemo(() => {
    const nextParams = new URLSearchParams(location.search)
    nextParams.set(PERIOD_PARAM, periodValue)
    nextParams.delete(START_DATE_PARAM)
    nextParams.delete(END_DATE_PARAM)
    return {
      pathname: location.pathname,
      search: nextParams.toString(),
    }
  }, [periodValue, location.pathname, location.search])

  const announceLink = useCallback(
    () => announce(InsightsResources.periodNavigationLinkAnnouncement(ariaLabel ?? children)),
    [ariaLabel, children],
  )

  return (
    <li>
      <Link
        key={periodValue}
        aria-current={selected}
        aria-label={ariaLabel}
        to={to}
        onClick={announceLink}
        className={clsx(styles.PeriodNavigationLink, selected && styles.Selected)}
      >
        {children}
      </Link>
    </li>
  )
}

export function PeriodNavigation({period}: {period: MemexChartTimePeriod}) {
  return (
    <nav aria-label="Time period">
      <ul className={styles.PeriodNavigation}>
        {PERIOD_OPTIONS.map((periodValue, periodIndex) => (
          <PeriodNavigationLink
            key={periodValue.value}
            periodValue={periodValue.value}
            selected={period === periodValue.value || (!period && periodIndex === 0)}
            aria-label={periodValue.ariaLabel}
          >
            {periodValue.text ?? periodValue.value}
          </PeriodNavigationLink>
        ))}
      </ul>
    </nav>
  )
}

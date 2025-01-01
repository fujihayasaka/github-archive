import type {BaseDateBucket} from '../../types/copilot-metrics'
import {Text} from '@primer/react'
import styles from './CopilotMetricsTable.module.css'
import {rollingDateRangeString} from '../../helpers/date'

export interface Props {
  row: BaseDateBucket
}

export function WeekCell({row}: Props) {
  return (
    <div className="d-flex flex-column">
      <Text weight="semibold" className={styles.weekLabel}>
        {row.label}
      </Text>
      <Text weight="light" className={styles.weekSubLabel}>
        {rollingDateRangeString(row.startDate, row.endDate)}
      </Text>
    </div>
  )
}

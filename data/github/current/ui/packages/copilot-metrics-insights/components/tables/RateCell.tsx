import type {AcceptanceCounts} from '../../types/copilot-metrics'
import {Text} from '@primer/react'
import styles from './CopilotMetricsTable.module.css'

type Props = {
  counts: AcceptanceCounts
  unit: string
}

export function RateCell({counts, unit}: Props) {
  return (
    <div className="d-flex flex-column">
      <span>{Math.round(counts.acceptanceRate * 100)}%</span>
      <Text weight="light" className={styles.weekSubLabel}>
        {counts.accepted.toLocaleString()} of {counts.total.toLocaleString()} {unit}
      </Text>
    </div>
  )
}

import {Stack} from '@primer/react'
import {clsx} from 'clsx'
import styles from './SummarySection.module.css'

interface SummarySectionProps {
  // we expect 1-3 summaries
  summaries:
    | [React.ReactNode]
    | [React.ReactNode, React.ReactNode]
    | [React.ReactNode, React.ReactNode, React.ReactNode]
}

export function SummarySection({summaries}: SummarySectionProps) {
  return (
    <div className="mb-3">
      <Stack direction="horizontal" gap="spacious" className="pb-0" align="stretch">
        {summaries.map(summary => {
          const key = (summary as React.ReactElement)?.key ?? undefined
          return (
            <div key={key} className={clsx('Box', styles.box, 'p-3', styles.border)}>
              {summary}
            </div>
          )
        })}
      </Stack>
    </div>
  )
}

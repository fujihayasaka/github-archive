import {GraphIcon} from '@primer/octicons-react'
import styles from './CopilotMetricsChart.module.css'
import {clsx} from 'clsx'
import {useEffect, useState} from 'react'

export interface CopilotMetricsChartLoadingProps {
  title: string
  delay?: number
}

export function CopilotMetricsChartLoading({title, delay = 500}: CopilotMetricsChartLoadingProps) {
  const [showLoading, setShowLoading] = useState(false)

  useEffect(() => {
    const timeout = window.setTimeout(() => setShowLoading(true), delay)

    return () => window.clearTimeout(timeout)
  }, [delay])

  const showLoadingBlankslate = () => {
    if (showLoading) {
      return (
        <>
          <GraphIcon className="fgColor-muted" size={24} />
          <h2 className="f3" data-testid="copilot-metrics-chart-loading-title">
            {title}
          </h2>
        </>
      )
    }
  }

  return (
    <div
      className={clsx(styles.CopilotMetricsChart, 'border rounded-2 flex-items-center flex-justify-center')}
      data-testid="copilot-metrics-chart-loading"
    >
      {showLoadingBlankslate()}
    </div>
  )
}

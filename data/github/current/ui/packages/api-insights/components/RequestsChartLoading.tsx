import {GraphIcon} from '@primer/octicons-react'
import styles from './RequestsChart.module.css'
import {clsx} from 'clsx'
import {useEffect, useState} from 'react'

export interface RequestsChartLoadingProps {
  title: string
  delay?: number
}

export function RequestsChartLoading({title, delay = 500}: RequestsChartLoadingProps) {
  // Primer guidelines note that we should not show a loading state for fast actions
  const [showLoading, setShowLoading] = useState(false)
  useEffect(() => {
    const timeout = window.setTimeout(() => {
      setShowLoading(true)
    }, delay)

    return () => {
      window.clearTimeout(timeout)
    }
  }, [delay])
  return (
    <div className={clsx(styles.requestsChart, 'position-relative width-full')} data-testid="requests-chart-loading">
      <div className="border rounded-2 d-flex flex-items-center flex-justify-center height-full flex-column">
        {showLoading && <GraphIcon className="fgColor-muted" size={24} />}
        {showLoading && (
          <h2 className="f3" data-testid="requests-chart-loading-title">
            {title}
          </h2>
        )}
      </div>
    </div>
  )
}

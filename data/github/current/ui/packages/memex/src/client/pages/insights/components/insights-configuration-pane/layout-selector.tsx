import {testIdProps} from '@github-ui/test-id-props'
import {ActionList, ActionMenu} from '@primer/react'
import {useCallback, useId} from 'react'

import {chartLayouts, chartLayoutsMap} from '../../../../components/insights/chart-layouts'
import {useChartActions} from '../../../../state-providers/charts/use-chart-actions'
import type {ChartState} from '../../../../state-providers/charts/use-charts'
import {useSetNextChartParams} from '../../../../state-providers/charts/use-set-next-chart-params'
import styles from './layout-selector.module.css'
import {SelectorLabel} from './shared'
import sharedStyles from './shared.module.css'

export function LayoutSelector({chart}: {chart: ChartState}) {
  const {updateLocalChartConfiguration} = useChartActions()

  const {
    number: chartNumber,
    localVersion: {
      configuration: {type: localVersionType},
    },
  } = chart

  const selectedLayout = chartLayoutsMap[localVersionType]
  const {setNextChartParams} = useSetNextChartParams(chart)
  const handleUpdateLayout = useCallback(
    (nextLayout: (typeof chartLayouts)[0]) => {
      const nextConfig = {type: nextLayout.type}
      updateLocalChartConfiguration(chartNumber, nextConfig)
      setNextChartParams(nextConfig)
    },
    [updateLocalChartConfiguration, chartNumber, setNextChartParams],
  )

  const labelId = useId()
  const buttonId = useId()

  return (
    <div className={styles.Box}>
      <SelectorLabel id={labelId}>Layout</SelectorLabel>
      <ActionMenu>
        <ActionMenu.Button
          id={buttonId}
          aria-labelledby={`${labelId} ${buttonId}`}
          leadingVisual={selectedLayout?.icon}
          className={sharedStyles.SelectorDropdownButton}
        >
          {selectedLayout?.label ?? 'None'}
        </ActionMenu.Button>
        <ActionMenu.Overlay className={sharedStyles.SelectorDropdownOverlay}>
          <ActionList selectionVariant="single" {...testIdProps('chart-layout-list')}>
            {chartLayouts.map(chartLayout => {
              return (
                <ActionList.Item
                  key={chartLayout.type}
                  selected={chartLayout.type === localVersionType}
                  onSelect={() => handleUpdateLayout(chartLayout)}
                >
                  <ActionList.LeadingVisual>
                    <chartLayout.icon />
                  </ActionList.LeadingVisual>
                  {chartLayout.label}
                </ActionList.Item>
              )
            })}
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
    </div>
  )
}

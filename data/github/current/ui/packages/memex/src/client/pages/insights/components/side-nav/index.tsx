import {testIdProps} from '@github-ui/test-id-props'
import {PlusIcon} from '@primer/octicons-react'
import {Button, NavList} from '@primer/react'
import {memo, useCallback, useMemo} from 'react'
import {useParams} from 'react-router-dom'

import {partition} from '../../../../../utils/partition'
import type {MemexChartConfiguration} from '../../../../api/charts/contracts/api'
import {InsightsChartNavigation} from '../../../../api/stats/contracts'
import {chartLayoutsMap} from '../../../../components/insights/chart-layouts'
import {ViewerPrivileges} from '../../../../helpers/viewer-privileges'
import {usePostStats} from '../../../../hooks/common/use-post-stats'
import {useNavigate} from '../../../../router'
import {useProjectRouteParams} from '../../../../router/use-project-route-params'
import {PROJECT_INSIGHTS_NUMBER_ROUTE} from '../../../../routes'
import {getDirtyChartState, isDefaultChart} from '../../../../state-providers/charts/chart-helpers'
import {useChartActions} from '../../../../state-providers/charts/use-chart-actions'
import {type ChartState, useCharts} from '../../../../state-providers/charts/use-charts'
import {InsightsResources} from '../../../../strings'
import {ChartLink} from './chart-link'
import styles from './index.module.css'
import {InsightsChartOptions} from './insights-chart-options'

const AddChartButton = memo(function AddChartButton() {
  const {getCreateChartRequest} = useCharts()
  const {createChartConfiguration} = useChartActions()
  const navigate = useNavigate()
  const projectRouteParams = useProjectRouteParams()

  return (
    <>
      <Button
        {...testIdProps('add-chart-button')}
        onClick={useCallback(async () => {
          const createChartRequest = getCreateChartRequest()
          await createChartConfiguration.perform(createChartRequest)
          if (createChartConfiguration.status.current.status === 'succeeded') {
            const newChart = createChartConfiguration.status.current.data
            navigate(
              PROJECT_INSIGHTS_NUMBER_ROUTE.generatePath({
                ...projectRouteParams,
                insightNumber: newChart.chart.number,
              }),
            )
          }
        }, [getCreateChartRequest, createChartConfiguration, navigate, projectRouteParams])}
        leadingVisual={PlusIcon}
        className={styles.Button}
      >
        {InsightsResources.sideNavNewChartButton}
      </Button>
    </>
  )
})

function sortChartsByName(chartA: ChartState, chartB: ChartState) {
  return chartA.name.localeCompare(chartB.name)
}

interface ChartItemTrailingVisualProps {
  chartConfiguration: ChartState
  isActiveChart: boolean
}

const ChartItemTrailingVisual: React.FC<ChartItemTrailingVisualProps> = ({chartConfiguration, isActiveChart}) => {
  const {hasWritePermissions} = ViewerPrivileges()

  return (
    <div className={styles.Box}>
      {isActiveChart && hasWritePermissions ? <InsightsChartOptions chart={chartConfiguration} /> : null}
    </div>
  )
}

export const InsightsSideNav = () => {
  const {hasWritePermissions} = ViewerPrivileges()
  const params = useParams()
  const {chartConfigurations, getChartLinkTo} = useCharts()
  const {postStats} = usePostStats()
  const insightNumber = params.insightNumber ? Number(params.insightNumber) : 0
  const {defaultCharts, myCharts} = useMemo(() => {
    const [defaultChartConfigs, customChartConfigs] = partition(Object.values(chartConfigurations), isDefaultChart)

    return {
      defaultCharts: defaultChartConfigs.sort(sortChartsByName),
      myCharts: customChartConfigs.sort(sortChartsByName),
    }
  }, [chartConfigurations])

  const postChartNavigationStats = useCallback(
    (chartNumber: number, configuration: MemexChartConfiguration) => {
      postStats({
        name: InsightsChartNavigation,
        context: JSON.stringify({chartNumber, ...configuration}),
      })
    },
    [postStats],
  )

  return (
    <>
      <NavList className={styles.NavList} {...testIdProps('insights-side-nav')}>
        <NavList.Group title={InsightsResources.sideNavDefaultCharts}>
          {defaultCharts.map(chartConfiguration => {
            const isActiveChart = insightNumber === 0
            const chartDirtyState = getDirtyChartState(chartConfiguration)
            const Icon = chartLayoutsMap[chartConfiguration.localVersion.configuration.type].icon

            return (
              <ChartLink
                key={chartConfiguration.number}
                {...testIdProps('default-chart-navigation-item')}
                isDirty={chartDirtyState.isDirty}
                to={getChartLinkTo(chartConfiguration.number).url}
                isActive={isActiveChart}
                leadingVisual={<Icon />}
                trailingVisual={
                  <ChartItemTrailingVisual chartConfiguration={chartConfiguration} isActiveChart={isActiveChart} />
                }
                // no navigation when already active
                onClick={e => {
                  if (isActiveChart) {
                    e.preventDefault()
                  } else {
                    postChartNavigationStats(chartConfiguration.number, chartConfiguration.localVersion.configuration)
                  }
                }}
              >
                {chartConfiguration.name}
              </ChartLink>
            )
          })}
        </NavList.Group>

        <NavList.Group title={InsightsResources.sideNavCustomCharts}>
          {myCharts.map(chartConfiguration => {
            const isActiveChart = insightNumber === chartConfiguration.number
            const chartDirtyState = getDirtyChartState(chartConfiguration)
            const Icon = chartLayoutsMap[chartConfiguration.localVersion.configuration.type].icon

            return (
              <ChartLink
                key={chartConfiguration.number}
                {...testIdProps('my-chart-navigation-item')}
                to={getChartLinkTo(chartConfiguration.number).url}
                isActive={isActiveChart}
                isDirty={chartDirtyState.isDirty}
                leadingVisual={<Icon />}
                trailingVisual={
                  <ChartItemTrailingVisual chartConfiguration={chartConfiguration} isActiveChart={isActiveChart} />
                }
                // no navigation when already active
                onClick={e => {
                  if (isActiveChart) {
                    e.preventDefault()
                  } else {
                    postChartNavigationStats(chartConfiguration.number, chartConfiguration.localVersion.configuration)
                  }
                }}
              >
                {chartConfiguration.name}
              </ChartLink>
            )
          })}
        </NavList.Group>
      </NavList>
      {hasWritePermissions && (
        <div>
          <AddChartButton />
        </div>
      )}
    </>
  )
}

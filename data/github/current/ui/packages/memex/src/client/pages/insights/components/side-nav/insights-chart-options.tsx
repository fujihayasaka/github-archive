import {testIdProps} from '@github-ui/test-id-props'
import {PencilIcon, TrashIcon, TriangleDownIcon, VersionsIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, IconButton, useConfirm} from '@primer/react'
import {useCallback, useRef, useState} from 'react'

import {PotentiallyDirty} from '../../../../components/potentially-dirty'
import {ViewerPrivileges} from '../../../../helpers/viewer-privileges'
import {useNavigate, useSearchParams} from '../../../../router'
import {useProjectRouteParams} from '../../../../router/use-project-route-params'
import {PROJECT_INSIGHTS_NUMBER_ROUTE} from '../../../../routes'
import {
  getDirtyChartState,
  getParamsForFullResetToServerState,
  isDefaultChart,
} from '../../../../state-providers/charts/chart-helpers'
import {useChartActions} from '../../../../state-providers/charts/use-chart-actions'
import {type ChartState, useCharts} from '../../../../state-providers/charts/use-charts'
import {Resources} from '../../../../strings'
import {useInsightsChartName} from '../../hooks/use-insights-chart-name'
import {useInsightsConfigurationPane} from '../../hooks/use-insights-configuration-pane'
import styles from './insights-chart-options.module.css'

interface InsightsChartOptionsProps {
  chart: ChartState
}

export const InsightsChartOptions = ({chart}: InsightsChartOptionsProps) => {
  const {isDirty, isConfigurationDirty} = getDirtyChartState(chart)
  const [, setSearchParams] = useSearchParams()
  const projectRouteParams = useProjectRouteParams()
  const [open, setOpen] = useState(false)
  const anchorRef = useRef<HTMLButtonElement>(null)
  const {hasWritePermissions} = ViewerPrivileges()
  const {saveChartName} = useInsightsChartName(chart)

  const onOpenChange = useCallback(
    (openState: React.SetStateAction<boolean>): void => {
      setOpen(openState)
      if (!openState) {
        saveChartName()
      }
    },
    [saveChartName],
  )

  const {
    destroyChartConfiguration,
    createChartConfiguration,
    updateChartConfiguration,
    resetLocalChangesForChartNumber,
  } = useChartActions()
  const navigate = useNavigate()
  const confirm = useConfirm()
  const {getChartLinkTo} = useCharts()

  type onSelectProp = NonNullable<React.ComponentProps<(typeof ActionList)['Item']>['onSelect']>

  const chartIsDefault = isDefaultChart(chart)
  const userDefinedChart = !chartIsDefault

  const handleDeleteChart: onSelectProp = useCallback(
    async e => {
      e.preventDefault()
      e.stopPropagation()
      if (chartIsDefault) return
      if (
        await confirm({
          title: 'Delete chart?',
          content: `Are you sure you want to delete "${chart.name}"?`,
          confirmButtonContent: 'Delete',
          confirmButtonType: 'danger',
        })
      ) {
        await destroyChartConfiguration.perform(chart.number)
        if (destroyChartConfiguration.status.current.status === 'succeeded') {
          navigate(getChartLinkTo(0).url)
        }
      }
    },
    [chart.name, chart.number, chartIsDefault, confirm, destroyChartConfiguration, getChartLinkTo, navigate],
  )

  const handleDuplicateChart: onSelectProp = useCallback(
    async e => {
      e.preventDefault()
      e.stopPropagation()
      const chartNumberToDuplicate = chart.number
      await createChartConfiguration.perform({
        chart: {
          configuration: chart.localVersion.configuration,
        },
      })
      if (createChartConfiguration.status.current.status === 'succeeded') {
        navigate(
          PROJECT_INSIGHTS_NUMBER_ROUTE.generatePath({
            ...projectRouteParams,
            insightNumber: createChartConfiguration.status.current.data.chart.number,
          }),
        )
      }
      resetLocalChangesForChartNumber(chartNumberToDuplicate)
    },
    [
      chart.localVersion.configuration,
      chart.number,
      createChartConfiguration,
      navigate,
      resetLocalChangesForChartNumber,
      projectRouteParams,
    ],
  )
  const handleSaveChanges: onSelectProp = useCallback(
    async e => {
      e.preventDefault()
      e.stopPropagation()
      if (chartIsDefault) return
      await updateChartConfiguration.perform({
        chartNumber: chart.number,
        chart: {
          configuration: {
            ...chart.localVersion.configuration,
          },
        },
      })
      setSearchParams(getParamsForFullResetToServerState(new URLSearchParams(window.location.search)))
    },
    [chart.localVersion.configuration, chart.number, chartIsDefault, setSearchParams, updateChartConfiguration],
  )
  const handleDiscardChanges: onSelectProp = useCallback(
    async e => {
      e.preventDefault()
      e.stopPropagation()

      resetLocalChangesForChartNumber(chart.number)
      setSearchParams(getParamsForFullResetToServerState(new URLSearchParams(window.location.search)))
    },
    [chart.number, resetLocalChangesForChartNumber, setSearchParams],
  )

  const {openPane} = useInsightsConfigurationPane()

  return (
    <>
      <PotentiallyDirty
        isDirty={isDirty}
        hideDirtyState={!hasWritePermissions}
        {...(isDirty ? testIdProps('chart-options-dirty') : undefined)}
      >
        <IconButton
          {...testIdProps('chart-options-button')}
          ref={anchorRef}
          aria-haspopup="true"
          aria-expanded={open}
          icon={TriangleDownIcon}
          onClick={useCallback((e: React.MouseEvent<HTMLButtonElement>) => {
            e.preventDefault()
            setOpen(s => !s)
          }, [])}
          aria-label="Chart options"
          className={styles.IconButton}
        />
      </PotentiallyDirty>
      <ActionMenu open={open} onOpenChange={onOpenChange} anchorRef={anchorRef}>
        <ActionMenu.Overlay width="medium" className={styles.ActionMenu_Overlay}>
          <ActionList>
            <ActionList.Item onSelect={openPane} {...testIdProps('chart-options-open-configure')}>
              <ActionList.LeadingVisual>
                <PotentiallyDirty isDirty={isConfigurationDirty}>
                  <PencilIcon />
                </PotentiallyDirty>
              </ActionList.LeadingVisual>
              Configure
            </ActionList.Item>
            <ActionList.Item onSelect={handleDuplicateChart}>
              <ActionList.LeadingVisual>
                <VersionsIcon />
              </ActionList.LeadingVisual>
              {isDirty ? 'Save changes to new chart' : 'Duplicate chart'}
            </ActionList.Item>
            {chartIsDefault ? null : (
              <ActionList.Item variant="danger" onSelect={handleDeleteChart}>
                <ActionList.LeadingVisual>
                  <TrashIcon />
                </ActionList.LeadingVisual>
                Delete chart
              </ActionList.Item>
            )}

            {isDirty ? (
              <>
                <ActionList.Divider />
                <ActionList.Group className={styles.ActionList_Group}>
                  {hasWritePermissions && userDefinedChart ? (
                    <ActionList.Item
                      onSelect={handleSaveChanges}
                      {...testIdProps('view-options-menu-save-changes-button')}
                      className={styles.ActionList_Item}
                    >
                      {Resources.saveChanges}
                    </ActionList.Item>
                  ) : null}
                  <ActionList.Item
                    onSelect={handleDiscardChanges}
                    {...testIdProps('chart-options-menu-reset-changes-button')}
                    className={styles.ActionList_Item_1}
                  >
                    {Resources.discardChanges}
                  </ActionList.Item>
                </ActionList.Group>
              </>
            ) : null}
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
    </>
  )
}

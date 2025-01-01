import type {MetricsItem, MetricsViewReadOnly} from '../models/models'
import {Observer} from '../observables/Observer'
import type {Column} from '@primer/react/experimental'
import {DataTable, Table} from '@primer/react/experimental'
import type {IMetricsService} from '../services/metrics-service'
import {Utils} from '../utils/utils'
import {ConditionalChildren} from '../observables/ConditionalChildren'
import {Services} from '../services/services'
import type {IAnalyticsService} from '../services/analytics-service'
import {OrderByDirection} from '../models/enums'
import {COLUMNS} from '../constants/constants'

export interface MetricsTableProps {
  metricsService: IMetricsService
}

export const MetricsTable = (props: MetricsTableProps) => {
  const analyticsService = Services.get<IAnalyticsService>('IAnalyticsService')
  const metricsService = props.metricsService
  const state = metricsService.getMetricsView()
  const columns = metricsService.getColumns()
  const data = metricsService.getMetrics()
  const loading = metricsService.getLoading()

  return (
    <Table.Container>
      <ConditionalChildren renderChildren={loading}>
        <Observer columns={columns} state={state}>
          {(obs: {columns: Array<Column<MetricsItem>>; state: MetricsViewReadOnly | undefined}) => {
            return <Table.Skeleton columns={obs.columns} rows={obs.state?.virtualPageSize} />
          }}
        </Observer>
      </ConditionalChildren>

      <ConditionalChildren renderChildren={loading} inverse>
        <Observer data={data} columns={columns} view={state}>
          {(obs: {data: MetricsItem[]; columns: Array<Column<MetricsItem>>; view: MetricsViewReadOnly}) => {
            const defaultOrderBy = metricsService.getDefaultOrderBy()
            const direction = obs.view.orderBy?.direction || defaultOrderBy.direction
            const field = obs.view.orderBy?.field || defaultOrderBy.field
            const initialSortDirection = direction === OrderByDirection.ORDER_BY_DIRECTION_DESC ? 'DESC' : 'ASC'
            const initialSortColumn = Utils.camelToSnake(field)

            let displayColumns = obs.columns

            if (obs.columns.find(c => c.id === COLUMNS.repository)) {
              // if we already have repo in columns then it is important to filter out the org column from display
              // because the repo column already includes the org data. The org column should not be completely
              // removed from config because it is necessary for export

              displayColumns = obs.columns.filter(c => c.id !== COLUMNS.organization)
            }

            return (
              <DataTable
                key={initialSortColumn + initialSortDirection + Math.random()} // not rendering correctly unless we use key to force total update
                data={obs.data}
                columns={displayColumns}
                initialSortDirection={initialSortDirection}
                initialSortColumn={initialSortColumn}
              />
            )
          }}
        </Observer>
      </ConditionalChildren>

      <Observer state={state}>
        {(obs: {state: MetricsViewReadOnly}) => {
          const defaultPageIndex = Utils.getCurrentPage(
            obs.state?.virtualOffset ?? 0,
            obs.state?.virtualPageSize ?? 0,
            obs.state?.totalItems,
          )
          return (
            obs.state.totalItems !== undefined && (
              <Table.Pagination
                key={defaultPageIndex + Math.random()} // not rendering correctly unless we use key to force total update
                aria-label="Pagination for table"
                pageSize={obs.state.virtualPageSize}
                totalCount={obs.state.totalItems}
                onChange={pageInfo => {
                  analyticsService.logEvent('pagination.change', 'MetricsTable', {
                    page: pageInfo.pageIndex,
                    previous: JSON.stringify(obs.state),
                  })
                  props.metricsService.setPage(pageInfo.pageIndex)
                }}
                defaultPageIndex={defaultPageIndex}
              />
            )
          )
        }}
      </Observer>
    </Table.Container>
  )
}

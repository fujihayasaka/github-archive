import {QueryRouteQueryType} from '@github-ui/react-core/future/data-router-types'
import {useQueriesConfigs, useRouteQuery} from '@github-ui/react-core/future/use-route-query'
import {Spinner} from '@primer/react'
import {useMemo} from 'react'
import styles from './styles.module.css'
import type {QueryRoute} from '@github-ui/react-core/future/query-route'

function FormattedJSON<T>({data}: {data: T}) {
  return <pre>{JSON.stringify(data, undefined, 2)}</pre>
}
function BlockingQueryData<
  Config extends // eslint-disable-next-line @typescript-eslint/no-explicit-any
    QueryRoute<any, any, any, any>,
  QueryName extends string & keyof Config['queries'],
>({route, queryName}: {route: Config; queryName: QueryName}) {
  const {data} = useRouteQuery(route, queryName)

  return <FormattedJSON data={data} />
}

function DeferredQueryData<
  Config extends // eslint-disable-next-line @typescript-eslint/no-explicit-any
    QueryRoute<any, any, any, any>,
  QueryName extends string & keyof Config['queries'],
>({route, queryName}: {route: Config; queryName: QueryName}) {
  const {data, isPending} = useRouteQuery(route, queryName)

  return isPending ? <Spinner /> : <FormattedJSON data={data} />
}

const TableRow = ({header, data}: {header: string; data: string}) => {
  return (
    <tr>
      <th className={styles.tableHeaderCell}>{header}</th>
      <td className={styles.tableCell}>{data}</td>
    </tr>
  )
}

function QueryStatus<
  Config extends // eslint-disable-next-line @typescript-eslint/no-explicit-any
    QueryRoute<any, any, any, any>,
  QueryName extends keyof Config['queries'],
>({route, queryName, type}: {route: Config; queryName: QueryName; type: QueryRouteQueryType}) {
  const {status, fetchStatus} = useRouteQuery(route, queryName.toString())

  return (
    <table>
      <tbody>
        <TableRow header="Name" data={queryName.toString()} />
        <TableRow header="Type" data={type} />
        <TableRow header="Status" data={status} />
        <TableRow header="FetchStatus" data={fetchStatus} />
      </tbody>
    </table>
  )
}

export function DisplayQueries<
  Config extends // eslint-disable-next-line @typescript-eslint/no-explicit-any
    QueryRoute<any, any, any, any>,
>({route}: {route: Config}) {
  const queries = useQueriesConfigs(route)
  const table = useMemo(() => {
    const _table: {
      headers: JSX.Element[]
      data: JSX.Element[]
      config: JSX.Element[]
    } = {
      headers: [
        <th className={styles.tableHeaderCell} key="info">
          Info
        </th>,
      ],
      data: [
        <th className={styles.tableHeaderCell} key="data">
          Data
        </th>,
      ],
      config: [
        <th className={styles.tableHeaderCell} key="config">
          Config
        </th>,
      ],
    }

    for (const [name, config] of objectEntries(queries)) {
      _table.headers.push(
        <th key={name.toString()} className={styles.tableHeaderCell}>
          <QueryStatus route={route} queryName={name} type={config.type} />
        </th>,
      )

      _table.config.push(
        <td key={name.toString()} className={styles.tableCell}>
          <FormattedJSON data={config.queryConfig} />
        </td>,
      )
      switch (config.type) {
        case QueryRouteQueryType.Blocking: {
          _table.data.push(
            <td
              key={`${name.toString()}-data`}
              data-testid={`${route.id}-${name.toString()}-data`}
              className={styles.tableCell}
            >
              <BlockingQueryData route={route} queryName={name.toString()} />
            </td>,
          )
          break
        }
        case QueryRouteQueryType.Deferred: {
          _table.data.push(
            <td key={`${name.toString()}-data`} className={styles.tableCell}>
              <DeferredQueryData route={route} queryName={name.toString()} />
            </td>,
          )
          break
        }
      }
    }
    return _table
  }, [queries, route])

  return (
    <table className={styles.table}>
      <thead>
        <tr>{table.headers}</tr>
      </thead>
      <tbody>
        <tr>{table.data}</tr>
        <tr>{table.config}</tr>
      </tbody>
    </table>
  )
}

const objectEntries = <T extends object>(obj: T) => {
  return Object.entries(obj) as Array<[keyof typeof obj, (typeof obj)[keyof typeof obj]]>
}

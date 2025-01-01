import type {QueryRoute} from '@github-ui/react-core/future/query-route'
import {useRouteQuery} from '@github-ui/react-core/future/use-route-query'

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function DisplayData({route}: {route: QueryRoute<any, any, any, any>}) {
  const {data} = useRouteQuery(route, 'mainQuery')

  return (
    <table id="payload-table">
      <thead>
        <tr>
          <th>someField</th>
          <th>serverTime</th>
        </tr>
      </thead>
      <tbody>
        <tr>
          <td>{data.someField}</td>
          <td>{data.serverTime}</td>
        </tr>
      </tbody>
    </table>
  )
}

import {useRouteQuery} from '@github-ui/react-core/future/use-route-query'
import {showSessionRoute} from '../routes/show-session'
import {PageHeader} from '@primer/react'

export function SessionHeader() {
  const payload = useRouteQuery(showSessionRoute, 'mainQuery')

  return <PageHeader>Session {payload.data.session.id}</PageHeader>
}

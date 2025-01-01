import {useRouteQuery} from '@github-ui/react-core/future/use-route-query'
import {someRouteRoute} from './some-route-route'

export function SomeRoute() {
  const payload = useRouteQuery(someRouteRoute, 'mainQuery')

  return (
    <>
      <h1 data-hpc>SomeRoute for test-react-data-router-app-package</h1>
      <article>{payload.data.someField}</article>
    </>
  )
}

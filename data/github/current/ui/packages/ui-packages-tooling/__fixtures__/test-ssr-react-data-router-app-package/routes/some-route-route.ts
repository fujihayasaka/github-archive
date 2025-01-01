import {mainQuery} from '@github-ui/react-core/future/main-query'
import {testSsrReactDataRouterAppPackageAppBuilder} from '../config/app-builder'

export type SomeRouteResponse = {
  someField: string
}

export const someRouteRoute = testSsrReactDataRouterAppPackageAppBuilder.createQueryRouteConfig('someRouteRoute', {
  path: '/some/:id/route',
  queries: [mainQuery<SomeRouteResponse>()],
})

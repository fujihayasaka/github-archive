import {mainQuery} from '@github-ui/react-core/future/main-query'
import {testReactDataRouterAppPackageAppBuilder} from '../config/app-builder'

export type SomeRouteResponse = {
  someField: string
}

export const someRouteRoute = testReactDataRouterAppPackageAppBuilder.createQueryRouteConfig('someRouteRoute', {
  path: '/some/:id/route',
  queries: [mainQuery<SomeRouteResponse>()],
})

import {mainQuery} from '@github-ui/react-core/future/main-query'
import {navigationTestsAppBuilder} from '../config/app-builder'
import type {Payload} from '../types/payload'

export const layoutRoute = navigationTestsAppBuilder.createQueryRouteConfig('layoutRoute', {
  path: '/_soft_navigation_tests',
  queries: [
    mainQuery<Payload>({
      queryDeps: ({pathname}) => ({pathname: `${pathname}/_layout`}),
    }),
  ],
})

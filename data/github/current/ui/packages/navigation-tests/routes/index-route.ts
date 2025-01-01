import {mainQuery} from '@github-ui/react-core/future/main-query'
import {navigationTestsAppBuilder} from '../config/app-builder'
import type {Payload} from '../types/payload'

export const indexRoute = navigationTestsAppBuilder.createQueryRouteConfig('indexRoute', {
  path: '/_soft_navigation_tests',
  index: true,
  queries: [mainQuery<Payload>()],
})

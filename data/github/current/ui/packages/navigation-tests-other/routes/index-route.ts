import {mainQuery} from '@github-ui/react-core/future/main-query'
import {navigationTestsOtherAppBuilder} from '../config/app-builder'
import type {Payload} from '../types/payload'

export const indexRoute = navigationTestsOtherAppBuilder.createQueryRouteConfig('indexRoute', {
  path: '/_soft_navigation_tests_other',
  queries: [mainQuery<Payload>()],
})

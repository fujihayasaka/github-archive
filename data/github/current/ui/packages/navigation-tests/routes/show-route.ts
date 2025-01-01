import {mainQuery} from '@github-ui/react-core/future/main-query'
import {navigationTestsAppBuilder} from '../config/app-builder'
import type {Payload} from '../types/payload'

export const showRoute = navigationTestsAppBuilder.createQueryRouteConfig('showRoute', {
  path: '/_soft_navigation_tests/:id',
  queries: [mainQuery<Payload>()],
})

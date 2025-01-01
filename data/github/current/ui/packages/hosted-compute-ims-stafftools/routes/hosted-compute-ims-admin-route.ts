import {mainQuery} from '@github-ui/react-core/future/main-query'
import {hostedComputeImsStafftoolsAppBuilder} from '../config/app-builder'
import type {MainPagePayload} from '../types/payloads'

export const hostedComputeImsAdminRoute = hostedComputeImsStafftoolsAppBuilder.createQueryRouteConfig(
  'hostedComputeImsAdminRoute',
  {
    path: '/stafftools/hosted_compute_ims_admin',
    queries: [mainQuery<MainPagePayload>()],
  },
)

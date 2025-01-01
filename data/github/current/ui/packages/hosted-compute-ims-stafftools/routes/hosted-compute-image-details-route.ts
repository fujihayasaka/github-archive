import {mainQuery} from '@github-ui/react-core/future/main-query'
import {hostedComputeImsStafftoolsAppBuilder} from '../config/app-builder'
import type {CuratedImageDetailsPagePayload} from '../types/payloads'

export const hostedComputeImageDetailsRoute = hostedComputeImsStafftoolsAppBuilder.createQueryRouteConfig(
  'hostedComputeImageDetailsRoute',
  {
    path: '/stafftools/hosted_compute_ims_admin/curated_images/:image_definition_id',
    queries: [mainQuery<CuratedImageDetailsPagePayload>()],
  },
)

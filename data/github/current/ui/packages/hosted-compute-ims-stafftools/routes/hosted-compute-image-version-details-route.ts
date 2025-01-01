import {mainQuery} from '@github-ui/react-core/future/main-query'
import {hostedComputeImsStafftoolsAppBuilder} from '../config/app-builder'
import type {CuratedImageVersionDetailsPagePayload} from '../types/payloads'

export const hostedComputeImageVersionDetailsRoute = hostedComputeImsStafftoolsAppBuilder.createQueryRouteConfig(
  'hostedComputeImageVersionDetailsRoute',
  {
    path: '/stafftools/hosted_compute_ims_admin/curated_images/:image_definition_id/versions/:version',
    queries: [mainQuery<CuratedImageVersionDetailsPagePayload>()],
  },
)

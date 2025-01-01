import {mainQuery} from '@github-ui/react-core/future/main-query'
import {codeQualityAppBuilder} from '../config/app-builder'
import type {Grade} from '../types/grade'

export type RepoCodeQualityIndexResponse = {
  owner: string
  repo: string
  lastScanAt: string
  maintainability: {
    grade: Grade
    findingsCount: number
  }
  reliability: {
    grade: Grade
    findingsCount: number
  }
}

export const repoCodeQualityIndexRoute = codeQualityAppBuilder.createQueryRouteConfig('repoCodeQualityIndexRoute', {
  path: '/:owner/:repo/security/quality',
  queries: [mainQuery<RepoCodeQualityIndexResponse>()],
})

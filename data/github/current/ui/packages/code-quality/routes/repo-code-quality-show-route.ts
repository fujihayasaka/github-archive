import {mainQuery} from '@github-ui/react-core/future/main-query'
import {codeQualityAppBuilder} from '../config/app-builder'
import type {RuleCategory} from '../types/rule-category'
import type {RuleSeverity} from '../types/rule-severity'

export type RepoCodeQualityShowResponse = {
  owner: string
  repo: string
  ruleId: string
  ruleTitle: string
  ruleDescription: string
  ruleHelp: string
  ruleCategory: RuleCategory
  ruleSeverity: RuleSeverity
  lastScanAt: string
  fileCount: number
}

export const repoCodeQualityShowRoute = codeQualityAppBuilder.createQueryRouteConfig('repoCodeQualityShowRoute', {
  path: '/:owner/:repo/security/quality/rules/:rule_id',
  queries: [mainQuery<RepoCodeQualityShowResponse>()],
})

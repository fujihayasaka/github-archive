import {http, HttpResponse} from 'msw'
import {repoCodeQualityIndexRoute} from '../../routes/repo-code-quality-index-route'
import {
  getRepoCodeQualityIndexRoutePayload,
  getRepoCodeQualityShowRoutePayload,
  getRuleFilesResponse,
  getRuleFindingsResponse,
  getRuleGroupsResponse,
} from '../../test-utils/mock-data'
import {codeQualityRuleFilesPath, codeQualityRuleFindingsPath, codeQualityRulesPath} from '@github-ui/paths'
import {repoCodeQualityShowRoute} from '../../routes/repo-code-quality-show-route'

export const repoCodeQualityIndexHandlers = [
  http.get(repoCodeQualityIndexRoute.generatePath({owner: 'octodemo', repo: 'repo1'}), () => {
    const response = {
      meta: {},
      payload: {
        [repoCodeQualityIndexRoute.id]: getRepoCodeQualityIndexRoutePayload(),
      },
    }
    return HttpResponse.json(response)
  }),

  http.get(codeQualityRulesPath({owner: 'octodemo', repo: 'repo1'}), () => {
    return HttpResponse.json(getRuleGroupsResponse())
  }),

  ...['rule-1', 'rule-2', 'rule-3'].map(ruleId =>
    http.get(codeQualityRuleFilesPath({owner: 'octodemo', repo: 'repo1', ruleId}), () => {
      return HttpResponse.json(getRuleFilesResponse())
    }),
  ),
]

export const repoCodeQualityShowHandlers = [
  http.get(repoCodeQualityShowRoute.generatePath({owner: 'octodemo', repo: 'repo1', rule_id: 'foo'}), () => {
    const response = {
      meta: {},
      payload: {
        [repoCodeQualityShowRoute.id]: getRepoCodeQualityShowRoutePayload(),
      },
    }
    return HttpResponse.json(response)
  }),

  http.get(codeQualityRuleFindingsPath({owner: 'octodemo', repo: 'repo1', ruleId: 'foo'}), () => {
    return HttpResponse.json(getRuleFindingsResponse())
  }),
]

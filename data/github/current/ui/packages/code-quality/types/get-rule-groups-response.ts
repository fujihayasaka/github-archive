import type {RuleGroup} from './rule-group'

export interface GetRuleGroupsResponse {
  rules: RuleGroup[]
  nextCursor: string
  prevCursor: string
}

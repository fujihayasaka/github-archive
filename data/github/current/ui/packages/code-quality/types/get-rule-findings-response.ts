import type {RuleFinding} from './rule-finding'

export interface GetRuleFindingsResponse {
  ruleFindings: RuleFinding[]
  findingsCount: number
  nextCursor: string
  prevCursor: string
}

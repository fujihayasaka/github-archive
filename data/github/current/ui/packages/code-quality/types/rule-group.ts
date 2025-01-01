import type {RuleCategory} from './rule-category'
import type {RuleSeverity} from './rule-severity'

export type RuleGroup = {
  title: string
  ruleId: string
  category: RuleCategory
  severity: RuleSeverity
  findingsCount: number
}

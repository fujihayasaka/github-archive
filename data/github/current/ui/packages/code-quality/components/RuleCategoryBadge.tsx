import {Label} from '@primer/react'
import {RuleCategory} from '../types/rule-category'

export type RuleCategoryBadgeProps = {
  category: RuleCategory
}

export function RuleCategoryBadge({category}: RuleCategoryBadgeProps) {
  switch (category) {
    case RuleCategory.Maintainability:
      return <Label variant="primary">Maintainability</Label>
    case RuleCategory.Reliability:
      return <Label variant="primary">Reliability</Label>
  }
}

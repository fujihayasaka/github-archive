import type {Icon} from '@primer/octicons-react'
import type {EvaluatorCfg} from './evals-sdk/config'

export type EvaluatorCategory = {
  name: string
}

export const EvaluatorTemplateCategories: Record<string, EvaluatorCategory> = {
  custom: {
    name: 'Custom',
  },
  quality: {
    name: 'Quality',
  },
  relevance: {
    name: 'Relevance',
  },
  comparative: {
    name: 'Comparative',
  },
  performance: {
    name: 'Performance',
  },
}

export type EvaluatorCategoryType = keyof typeof EvaluatorTemplateCategories

export type EvaluatorTemplate = {
  /** Name of the evaluator template in the list */
  displayName: string

  /** Description of the evaluator template in the list */
  description: string

  /** Icon to show in the list */
  icon?: Icon

  /** Optional category, templates will be grouped by their category */
  category?: EvaluatorCategoryType

  /** Config template for the evaluator */
  configTemplate: EvaluatorCfg

  /** Can this template be edited when creating or updating an evaluator? */
  readonly?: boolean
}

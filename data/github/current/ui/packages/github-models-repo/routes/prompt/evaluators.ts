import {NoteIcon, PencilIcon} from '@primer/octicons-react'
import type {EvaluatorLLM} from './evals-sdk/config'
import type {EvaluatorCategoryType, EvaluatorTemplate} from './evaluator-template'

// Available evaluator templates
export const EvaluatorTemplates: EvaluatorTemplate[] = [
  {
    displayName: 'String check',
    description: 'Check if the output contains a specific string',
    icon: NoteIcon,
    configTemplate: {
      name: '',
      string: {},
    },
  },
  {
    displayName: 'Custom prompt',
    description: 'Create a test criteria by writing your own prompt',
    icon: PencilIcon,
    configTemplate: {
      name: '',
      llm: {
        model: '',
        modelId: '',
        prompt: '',
        choices: [],
      } as EvaluatorLLM,
    },
  },
  {
    displayName: 'Similarity',
    description: 'Evaluates similarity score for QA scenario',
    category: 'quality',
    readonly: true,
    configTemplate: {
      name: 'Similarity',
      uses: 'github/similarity',
    },
  },
  {
    displayName: 'Coherence',
    description: 'Evaluates coherence score for QA scenario',
    category: 'quality',
    readonly: true,
    configTemplate: {
      name: 'Coherence',
      uses: 'github/coherence',
    },
  },
  {
    displayName: 'Fluency',
    description: 'Evaluates fluency score for QA scenario',
    category: 'quality',
    readonly: true,
    configTemplate: {
      name: 'Fluency',
      uses: 'github/fluency',
    },
  },
  {
    displayName: 'Relevance',
    description: 'Evaluates relevance score for QA scenario',
    category: 'relevance',
    readonly: true,
    configTemplate: {
      name: 'Relevance',
      uses: 'github/relevance',
    },
  },
  {
    displayName: 'Groundedness',
    description: 'Evaluates groundedness score for RAG scenario',
    category: 'relevance',
    readonly: true,
    configTemplate: {
      name: 'Groundedness',
      uses: 'github/groundedness',
    },
  },
]

export const GroupedEvaluatorTemplates: Record<EvaluatorCategoryType, EvaluatorTemplate[]> = EvaluatorTemplates.reduce<
  Record<EvaluatorCategoryType, EvaluatorTemplate[]>
>(
  (acc, template) => {
    const category = template.category ?? 'custom'
    if (!acc[category]) {
      acc[category] = []
    }
    acc[category].push(template)
    return acc
  },
  {} as Record<EvaluatorCategoryType, EvaluatorTemplate[]>,
)

import {Stack, Token} from '@primer/react'
import {useState, type ComponentProps} from 'react'
import {usePromptCompareState} from '../contexts/PromptCompareStateContext'
import type {EvaluatorCfg} from '../evals-sdk/config'
import {usePromptCompareManager} from '../prompt-compare-manager'
import {EvaluatorDialog} from './evaluators/EvaluatorDialog'
import styles from './EvaluatorOutlet.module.css'
import type {EvaluatorState} from '../prompts'

export function EvaluatorOutlet() {
  const manager = usePromptCompareManager()

  const {compare} = usePromptCompareState()
  const {evaluators} = compare

  const [editingEvaluator, setEditingEvaluator] = useState<{
    index: number
    config: EvaluatorCfg
  } | null>(null)

  function getEditableProps(evaluator: EvaluatorState, index: number): Partial<ComponentProps<typeof Token>> {
    if (evaluator.readonly)
      return {
        as: 'span',
      }

    return {
      as: 'button',
      onClick: () => setEditingEvaluator({index, config: evaluator.config}),
    }
  }

  return (
    <>
      {editingEvaluator != null && (
        <EvaluatorDialog
          evaluator={editingEvaluator.config}
          evaluatorIndex={editingEvaluator.index}
          onClose={() => {
            setEditingEvaluator(null)
          }}
        />
      )}

      <Stack direction="horizontal" wrap="wrap" gap="condensed">
        {evaluators.map((e, index) => (
          <Token
            key={`evaluator-${e.config.name}-${index}`}
            className={styles.Token}
            text={e.config.name}
            size="large"
            onRemove={() => manager.evalsRemoveEvaluator(index)}
            {...getEditableProps(e, index)}
          />
        ))}
      </Stack>
    </>
  )
}

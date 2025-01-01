import {useCallback, useState} from 'react'
import {usePromptCompareState} from '../contexts/PromptCompareStateContext'
import type {EvaluatorTemplate} from '../evaluator-template'
import {usePromptCompareManager} from '../prompt-compare-manager'
import {AddEvaluatorMenu} from './AddEvaluatorMenu'
import {EvaluatorDialog} from './evaluators/EvaluatorDialog'

export function AddEvaluatorButton() {
  const {compare} = usePromptCompareState()
  const {evaluators} = compare

  const manager = usePromptCompareManager()

  const [addEvaluatorTemplate, setAddEvaluatorTemplate] = useState<EvaluatorTemplate | null>(null)

  const handleEvalAdd = useCallback(
    (et: EvaluatorTemplate) => {
      if (et.readonly) {
        // Template cannot be customized, add directly
        manager.evalsAddEvaluator({
          config: et.configTemplate,
          readonly: true,
        })
        return
      }

      setAddEvaluatorTemplate(et)
    },
    [setAddEvaluatorTemplate, manager],
  )

  return (
    <>
      {addEvaluatorTemplate != null && (
        <EvaluatorDialog
          template={addEvaluatorTemplate}
          onClose={() => {
            setAddEvaluatorTemplate(null)
          }}
        />
      )}

      <AddEvaluatorMenu onSelectTemplate={handleEvalAdd} totalEvaluators={evaluators.length} />
    </>
  )
}

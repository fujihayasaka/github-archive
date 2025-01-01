import {type FormEvent, useCallback} from 'react'
import {FormControl, Textarea} from '@primer/react'
import type {EvaluatorLLM} from '../../evals-sdk/config'

interface SystemPromptControlProps {
  e: EvaluatorLLM
  readonly: boolean
  updateEvaluator: (evaluator: EvaluatorLLM) => void
}

export function SystemPromptControl({e, readonly, updateEvaluator}: SystemPromptControlProps) {
  const handleSystemPromptChange = useCallback(
    (evt: FormEvent<HTMLTextAreaElement>) => {
      updateEvaluator({
        ...e,
        systemPrompt: evt.currentTarget.value || undefined,
      })
    },
    [e, updateEvaluator],
  )

  return (
    <FormControl disabled={readonly} className="mb-3">
      <FormControl.Label>System prompt</FormControl.Label>
      <Textarea
        value={e.systemPrompt}
        resize="vertical"
        placeholder="Optional system prompt to use when prompting the model"
        block
        onInput={handleSystemPromptChange}
        rows={2}
        style={{height: '50px'}}
      />
    </FormControl>
  )
}

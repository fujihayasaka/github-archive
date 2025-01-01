import {type FormEvent, useCallback, useMemo, useState} from 'react'
import {InlineAutocomplete} from '@github-ui/inline-autocomplete'
import type {ShowSuggestionsEvent, Suggestion} from '@github-ui/inline-autocomplete/types'
import {FormControl, Textarea} from '@primer/react'
import type {EvaluatorLLM} from '../../evals-sdk/config'
import useActivePrompt from '../../hooks/use-active-prompt'
import {autocompletionVariablesInPrompt} from '../../variables'

interface PromptControlProps {
  e: EvaluatorLLM
  readonly: boolean
  updateEvaluator: (evaluator: EvaluatorLLM) => void
}

export function PromptControl({e, readonly, updateEvaluator}: PromptControlProps) {
  const activePrompt = useActivePrompt()
  const variableKeys = useMemo(() => autocompletionVariablesInPrompt(activePrompt), [activePrompt])

  const [variableSuggestions, setVariableSuggestions] = useState<Suggestion[]>([])

  const onShowSuggestions = useCallback(
    (_event: ShowSuggestionsEvent) => {
      setVariableSuggestions(variableKeys)
    },
    [variableKeys],
  )
  const onHideSuggestions = useCallback(() => {
    setVariableSuggestions([])
  }, [])
  const handlePromptChange = useCallback(
    (evt: FormEvent<HTMLTextAreaElement>) => {
      updateEvaluator({
        ...e,
        prompt: evt.currentTarget.value,
      })
    },
    [e, updateEvaluator],
  )

  return (
    <FormControl required disabled={readonly} className="mb-3">
      <FormControl.Label>Prompt</FormControl.Label>
      <InlineAutocomplete
        fullWidth
        tabInsertsSuggestions
        triggers={[
          {
            triggerChar: '{{',
            keepTriggerCharOnCommit: false,
          },
        ]}
        suggestions={variableSuggestions}
        onShowSuggestions={onShowSuggestions}
        onHideSuggestions={onHideSuggestions}
      >
        <Textarea
          value={e.prompt}
          resize="vertical"
          placeholder="Enter your prompt. You can reference your variables with {{variable_name}} and the model output with {{completion}}."
          block
          onInput={handlePromptChange}
          rows={4}
          style={{height: '150px'}}
        />
      </InlineAutocomplete>
    </FormControl>
  )
}

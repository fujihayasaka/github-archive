import {InlineAutocomplete} from '@github-ui/inline-autocomplete'
import type {ShowSuggestionsEvent, Suggestion} from '@github-ui/inline-autocomplete/types'
import {Checkbox, FormControl, Select, Textarea} from '@primer/react'

import {useCallback, useMemo, useState, type FormEvent} from 'react'
import type {EvaluatorString} from '../../evals-sdk/config'
import useActivePrompt from '../../hooks/use-active-prompt'
import {autocompletionVariablesInPrompt} from '../../variables'

export type StringCheckContent = {
  e: EvaluatorString
  readonly: boolean
  updateEvaluator: (evaluator: EvaluatorString) => void
}

export function StringCheckContent({e, readonly, updateEvaluator}: StringCheckContent) {
  const activePrompt = useActivePrompt()
  const variableKeys = useMemo(() => autocompletionVariablesInPrompt(activePrompt), [activePrompt])

  const operation = getOperation(e)

  // TODO: Make this a re-usable component
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

  const handleInput = useCallback(
    (evt: FormEvent<HTMLTextAreaElement>) => {
      updateEvaluator({
        ...e,
        [operation]: evt.currentTarget.value,
      })
    },
    [e, operation, updateEvaluator],
  )

  return (
    <>
      <FormControl disabled={readonly}>
        <FormControl.Label>Operation</FormControl.Label>
        <Select
          value={operation}
          onChange={evt =>
            updateEvaluator({
              [evt.target.value]: e[operation],
            })
          }
        >
          <Select.Option value="contains">contains</Select.Option>
          <Select.Option value="startsWith">startsWith</Select.Option>
          <Select.Option value="endsWith">endsWith</Select.Option>
        </Select>
      </FormControl>

      {operation === 'contains' && (
        <FormControl>
          <Checkbox
            checked={e.strict ?? false}
            onChange={evt =>
              updateEvaluator({
                ...e,
                strict: evt.currentTarget.checked ?? false,
              })
            }
          />
          <FormControl.Label>Case-sensitive</FormControl.Label>
        </FormControl>
      )}

      <FormControl required disabled={readonly} sx={{mb: 3}}>
        <FormControl.Label>Value</FormControl.Label>
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
            value={e[operation]}
            resize="vertical"
            placeholder="Value to check. Add variables with {{variable_name}}"
            block
            onInput={handleInput}
            rows={1}
            style={{height: '50px'}}
          />
        </InlineAutocomplete>
      </FormControl>
    </>
  )
}

function getOperation(e: EvaluatorString): 'contains' | 'startsWith' | 'endsWith' {
  if ('startsWith' in e) {
    return 'startsWith'
  }

  if ('endsWith' in e) {
    return 'endsWith'
  }

  // Default to contains
  return 'contains'
}

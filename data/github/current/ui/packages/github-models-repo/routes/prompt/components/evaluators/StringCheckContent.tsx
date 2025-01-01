import {InlineAutocomplete} from '@github-ui/inline-autocomplete'
import type {ShowSuggestionsEvent, Suggestion} from '@github-ui/inline-autocomplete/types'
import {FormControl, Select, Textarea} from '@primer/react'

import {useCallback, useState, type FormEvent} from 'react'
import type {EvaluatorString} from '../../evals-sdk/config'

export function validateStringCheck(e: EvaluatorString): string | null {
  if (!e.contains && !e.startsWith && !e.endsWith) {
    return 'Value is required'
  }

  return null
}

export type StringCheckContent = {
  e: EvaluatorString
  readonly: boolean
  updateEvaluator: (evaluator: EvaluatorString) => void
}

export function StringCheckContent({e, readonly, updateEvaluator}: StringCheckContent) {
  const operation = getOperation(e)

  // TODO: Make this a re-usable component
  const [variableSuggestions, setVariableSuggestions] = useState<Suggestion[]>([])
  const onShowSuggestions = useCallback((_event: ShowSuggestionsEvent) => {
    // TODO: Get this from evals state, or separate Variables UI
    setVariableSuggestions(['{{input}}', '{{expected}}', '{{completion}}'])
  }, [])
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
            placeholder="Value to check. Add variables with {{variable}}"
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
  if (e.startsWith) {
    return 'startsWith'
  }

  if (e.endsWith) {
    return 'endsWith'
  }

  // Default to contains
  return 'contains'
}

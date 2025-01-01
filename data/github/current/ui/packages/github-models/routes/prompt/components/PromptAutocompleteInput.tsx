import type {ShowSuggestionsEvent, Suggestion} from '@github-ui/inline-autocomplete/types'
import {FormControl, Textarea} from '@primer/react'
import {useCallback, useEffect, useRef, useState} from 'react'
import styles from './PromptAutoCompleteInput.module.css'
import {InlineAutocomplete} from '@github-ui/inline-autocomplete'
import {testIdProps} from '@github-ui/test-id-props'
import {debounce} from '@github/mini-throttle'
import {ImprovePrompt} from '../../playground/components/ImprovePrompt'

export type PromptAutocompleteInputProps = {
  label: string
  prompt: string
  setPromptInput: (prompt: string) => void
  variableKeys: string[]
  textareaPlaceholder: string
  showImprovePrompt?: boolean
}

export function PromptAutocompleteInput({
  label,
  prompt,
  setPromptInput,
  variableKeys,
  textareaPlaceholder,
  showImprovePrompt,
}: PromptAutocompleteInputProps) {
  const [variableSuggestions, setVariableSuggestions] = useState<Suggestion[]>([])
  const textareaRef = useRef<HTMLTextAreaElement>(null)
  const styledTextarea = useRef<HTMLPreElement>(null)
  const containerRef = useRef<HTMLDivElement>(null)

  // splits prompt based on variable structure {{ }}
  const REGEX_SPLIT_VARIABLES = /(\{\{[^}]*\}\})/
  const REGEX_IS_VARIABLE = /^\{\{.*\}\}$/

  const syncScroll = useCallback(() => {
    if (textareaRef.current && styledTextarea.current) {
      styledTextarea.current.scrollTop = textareaRef.current.scrollTop
    }
  }, [])

  const onShowSuggestions = useCallback(
    (_event: ShowSuggestionsEvent) => {
      setVariableSuggestions(variableKeys.map(key => `{{${key}}}`))
    },
    [variableKeys],
  )

  const onHideSuggestions = () => {
    setVariableSuggestions([])
  }

  const handlePromptInput = useCallback(
    (event: React.ChangeEvent<HTMLTextAreaElement>) => {
      syncScroll()

      const promptInput = event.target.value
      setPromptInput(promptInput)
    },
    [setPromptInput, syncScroll],
  )

  const getStylizedText = () => {
    if (!prompt) {
      return ''
    }
    // pre does not handle new lines properly at end of value. So we need to manually
    // add a space at the end in order for the stylized text and textarea to line up
    const updatedPrompt = prompt[prompt.length - 1] === '\n' ? `${prompt} ` : prompt

    return updatedPrompt.split(REGEX_SPLIT_VARIABLES).map((part, index) => {
      if (part.match(REGEX_IS_VARIABLE)) {
        const spanKey = `${part}-${index}`
        return (
          <span key={spanKey} className={styles.variableHighlight} {...testIdProps(`variable-highlight-${spanKey}`)}>
            {part}
          </span>
        )
      }
      return part
    })
  }

  const adjustHeight = useCallback(() => {
    if (textareaRef.current && containerRef.current) {
      containerRef.current.style.height = textareaRef.current.style.height
    }
    syncScroll()
  }, [syncScroll])

  useEffect(() => {
    const observer = new ResizeObserver(debounce(adjustHeight))

    if (textareaRef.current) {
      observer.observe(textareaRef.current)
    }

    return () => {
      observer.disconnect()
    }
  }, [adjustHeight])

  return (
    <FormControl>
      <FormControl.Label className="d-flex flex-justify-between flex-items-end width-full">
        {label}
        {showImprovePrompt && <ImprovePrompt prompt={prompt} handleUpdatePrompt={setPromptInput} />}
      </FormControl.Label>
      <div className={styles.promptInputContainer} ref={containerRef}>
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
          className={styles.inlineContainer}
        >
          <Textarea
            value={prompt}
            onChange={handlePromptInput}
            onScroll={syncScroll}
            placeholder={textareaPlaceholder}
            ref={textareaRef}
            resize="vertical"
            className={styles.promptInput}
            block
          />
        </InlineAutocomplete>
        <pre
          className={styles.styledPromptInput}
          aria-hidden="true"
          ref={styledTextarea}
          {...testIdProps('stylized-input')}
        >
          {getStylizedText()}
        </pre>
      </div>
    </FormControl>
  )
}

import '@github/g-emoji-element'

import {subscribe as subscribeToMarkdownPasting} from '@github/paste-markdown'
import {InlineAutocomplete} from '@github-ui/inline-autocomplete'
import {useAutocompleteTriggersAndSuggestions} from '@github-ui/inline-autocomplete/hooks/use-autocomplete-triggers-and-suggestions'
import {useDynamicTextareaHeight} from '@github-ui/use-dynamic-textarea-height'
import {Textarea, type TextareaProps, useRefObjectAsForwardedRef} from '@primer/react'
import {clsx} from 'clsx'
import {forwardRef, useEffect, useMemo, useRef} from 'react'

import styles from './MarkdownInput.module.css'
import type {SuggestionOptions} from './suggestions'
import {type Emoji, useEmojiSuggestions} from './suggestions/use-emoji-suggestions'
import {type Mentionable, useMentionSuggestions} from './suggestions/use-mention-suggestions'
import {type Reference, useReferenceSuggestions} from './suggestions/use-reference-suggestions'

interface MarkdownInputProps extends Omit<TextareaProps, 'onChange'> {
  value: string
  onChange?: React.ChangeEventHandler<HTMLTextAreaElement>
  onInput?: React.EventHandler<React.SyntheticEvent<HTMLTextAreaElement>>
  onKeyDown?: React.KeyboardEventHandler<HTMLTextAreaElement>
  disabled?: boolean
  placeholder?: string
  id: string
  maxLength?: number
  fullHeight?: boolean
  isDraggedOver: boolean
  emojiSuggestions?: SuggestionOptions<Emoji>
  emojiTone?: number
  mentionSuggestions?: SuggestionOptions<Mentionable>
  referenceSuggestions?: SuggestionOptions<Reference>
  labelledBy?: string
  minHeightLines: number
  maxHeightLines: number
  monospace: boolean
  pasteUrlsAsPlainText: boolean
  /** Use this prop to control visibility instead of unmounting, so the undo stack and custom height are preserved. */
  visible: boolean
}

const emptyArray: [] = [] // constant reference to avoid re-running effects

export const MarkdownInput = forwardRef<HTMLTextAreaElement, MarkdownInputProps>(
  (
    {
      value,
      onChange,
      onInput,
      disabled,
      placeholder,
      id,
      maxLength,
      onKeyDown,
      fullHeight,
      isDraggedOver,
      emojiSuggestions,
      emojiTone,
      mentionSuggestions,
      referenceSuggestions,
      labelledBy,
      minHeightLines,
      maxHeightLines,
      visible,
      monospace,
      pasteUrlsAsPlainText,
      className,
      ...props
    },
    forwardedRef,
  ) => {
    const emojiConfig = useMemo(() => ({tone: emojiTone}), [emojiTone])
    const {trigger: emojiTrigger, calculateSuggestions: calculateEmojiSuggestions} = useEmojiSuggestions(
      emojiSuggestions ?? emptyArray,
      emojiConfig,
    )
    const {trigger: mentionsTrigger, calculateSuggestions: calculateMentionSuggestions} = useMentionSuggestions(
      mentionSuggestions ?? emptyArray,
    )
    const {trigger: referencesTrigger, calculateSuggestions: calculateReferenceSuggestions} = useReferenceSuggestions(
      referenceSuggestions ?? emptyArray,
    )

    const triggersAndSuggestions = useMemo(
      () => [
        {trigger: emojiTrigger, suggestionsCalculator: calculateEmojiSuggestions},
        {trigger: mentionsTrigger, suggestionsCalculator: calculateMentionSuggestions},
        {trigger: referencesTrigger, suggestionsCalculator: calculateReferenceSuggestions},
      ],
      [
        calculateEmojiSuggestions,
        calculateMentionSuggestions,
        calculateReferenceSuggestions,
        emojiTrigger,
        mentionsTrigger,
        referencesTrigger,
      ],
    )

    const {triggers, suggestions, setSuggestionEvent, onHideSuggestions} =
      useAutocompleteTriggersAndSuggestions(triggersAndSuggestions)

    const ref = useRef<HTMLTextAreaElement>(null)
    useRefObjectAsForwardedRef(forwardedRef, ref)

    useEffect(() => {
      const subscription =
        ref.current &&
        subscribeToMarkdownPasting(ref.current, {defaultPlainTextPaste: {urlLinks: pasteUrlsAsPlainText}})
      return subscription?.unsubscribe
    }, [pasteUrlsAsPlainText])

    const heightStyles = useDynamicTextareaHeight({
      // if fullHeight is enabled, there is no need to compute a dynamic height (for perfs reasons)
      disabled: fullHeight || !visible,
      maxHeightLines,
      minHeightLines,
      elementRef: ref,
      value,
    })

    // See https://github.com/github/issues/issues/8807#issuecomment-1952063523. Workaround until the React bug is fixed (https://github.com/facebook/react/issues/28360)
    // This sets the DOM node directly to avoid the Safari bug where the user couldn't type after removing a line
    useEffect(() => {
      if (ref.current) {
        ref.current.value = value
      }
    })

    return (
      <InlineAutocomplete
        triggers={triggers}
        suggestions={suggestions}
        onShowSuggestions={setSuggestionEvent}
        onHideSuggestions={onHideSuggestions}
        style={{flex: 'auto'}}
        tabInsertsSuggestions
      >
        <Textarea
          id={id}
          ref={ref}
          placeholder={placeholder}
          maxLength={maxLength}
          onKeyDown={onKeyDown}
          disabled={disabled}
          aria-label={labelledBy ? undefined : 'Markdown value'}
          aria-labelledby={labelledBy}
          onChange={onChange}
          onInput={onInput}
          value={value}
          className={clsx(
            className,
            styles.textArea,
            !visible && styles.displayNone,
            fullHeight && styles.fullHeight,
            monospace && styles.monospace,
            isDraggedOver && styles.isDraggedOver,
          )}
          rows={minHeightLines}
          style={heightStyles}
          {...props}
        />
      </InlineAutocomplete>
    )
  },
)
MarkdownInput.displayName = 'MarkdownInput'

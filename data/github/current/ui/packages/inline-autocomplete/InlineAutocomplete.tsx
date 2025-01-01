import {throttle} from '@github/mini-throttle'
import {IS_BROWSER} from '@github-ui/ssr-utils'
import {ScopedCommands} from '@github-ui/ui-commands'
import {useSyntheticChange} from '@github-ui/use-synthetic-change'
import {Portal, useFormControlForwardedProps, useRefObjectAsForwardedRef} from '@primer/react'
import {clsx} from 'clsx'
import {InputRange} from 'dom-input-range'
import type React from 'react'
import {cloneElement, type CSSProperties, useEffect, useId, useRef, useState} from 'react'

import AutocompleteSuggestions from './AutocompleteSuggestions'
import styles from './InlineAutocomplete.module.css'
import type {
  SelectSuggestionsEvent,
  ShowSuggestionsEvent,
  Suggestion,
  Suggestions,
  SuggestionsPlacement,
  TextInputCompatibleChild,
  TextInputElement,
  Trigger,
} from './types'
import {
  augmentHandler,
  calculateSuggestionsQuery,
  getSuggestionKey,
  getSuggestionValue,
  isNullSuggestion,
  requireChildrenToBeInput,
} from './utils'

export type InlineAutocompleteProps = {
  /** Register the triggers that can cause suggestions to appear. */
  triggers: Trigger[]
  /**
   * Called when a valid suggestion query is updated. This should be handled by setting the
   * `suggestions` prop accordingly.
   */
  onShowSuggestions: (event: ShowSuggestionsEvent) => void

  /**
   * Called when a suggestion is selected.
   *
   * @note This should be used only for performing side effects, not for modifying
   * the inserted text. Do not call `setState` in this handler or the user's cursor
   * position / undo history could be lost.
   */
  onSelectSuggestion?: (event: SelectSuggestionsEvent) => void

  /** Called when suggestions should be hidden. Set `suggestions` to `null` in this case. */
  onHideSuggestions: () => void
  /**
   * The currently visible list of suggestions. If `loading`, a loading indicator will be
   * shown. If `null` or empty, the list will be hidden. Suggestion sort will be preserved.
   *
   * Typically, this should not contain more than five or so suggestions.
   */
  suggestions: Suggestions | null
  /**
   * If `true`, suggestions will be applied with both `Tab` and `Enter`, instead of just
   * `Enter`. This may be expected behavior for users used to IDEs, but use caution when
   * hijacking browser tabbing capability.
   * @default false
   */
  tabInsertsSuggestions?: boolean
  /**
   * The `AutocompleteTextarea` has a container for positioning the suggestions overlay.
   * This can break some layouts (ie, if the editor must expand with `flex: 1` to fill space)
   * so you can override container styles here. Usually this should not be necessary.
   * `position` may not be overridden.
   */
  style?: Omit<CSSProperties, 'position'>
  // Typing this as such makes it look like a compatible child internally, but it isn't actually
  // enforced externally so we have to resort to a runtime assertion.
  /**
   * An `input` or `textarea` compatible component to extend. A compatible component is any
   * component that forwards a ref and props to an underlying `input` or `textarea` element,
   * including but not limited to `Input`, `TextArea`, `input`, `textarea`, `styled.input`,
   * and `styled.textarea`. If the child is not compatible, a runtime `TypeError` will be
   * thrown.
   */
  children: TextInputCompatibleChild
  /**
   * Control which side of the insertion point the suggestions list appears on by default. This
   * should almost always be `"below"` because it typically provides a better user experience
   * (the most-relevant suggestions will appear closest to the text). However, if the input
   * is always near the bottom of the screen (ie, a chat composition form), it may be better to
   * display the suggestions above the input.
   *
   * In either case, if there is not enough room to display the suggestions in the default direction,
   * the suggestions will appear in the other direction.
   * @default "below"
   */
  suggestionsPlacement?: SuggestionsPlacement
  /**
   * The name of the portal to render the suggestions overlay into. This is useful if you
   * have multiple inline autocomplete components on the same page and you want to ensure
   * the suggestions overlay is rendered in the correct order.
   */
  portalName?: string
  /**
   * If `true`, the input will be rendered as a block element, taking up the full width of
   * its container. This is useful for rendering the input in a `flex` container, for example.
   */
  fullWidth?: boolean
  /** Optional title/name for the suggestions menu.  */
  title?: string
  /**
   * For simple cases, the standard representation of this widget is as a `listbox` tied to a `combobox`. For more
   * advanced cases (such as multistep menus or if items need to perform side effects), the widget can instead be
   * represented as a `menu` tied to a plain `textbox`.
   */
  asMenu?: boolean
}

const getSelectionStart = (element: TextInputElement) => {
  try {
    return element.selectionStart
  } catch (e: unknown) {
    // Safari throws an exception when trying to access selectionStart on date input element
    if (e instanceof TypeError) return null
    throw e
  }
}

const noop = () => {
  // don't do anything
}

/**
 * Shows suggestions to complete the current word/phrase the user is actively typing.
 */
export const InlineAutocomplete = ({
  triggers,
  suggestions,
  onShowSuggestions,
  onHideSuggestions,
  onSelectSuggestion,
  style,
  children,
  tabInsertsSuggestions = false,
  suggestionsPlacement = 'below',
  portalName,
  fullWidth = false,
  title: menuTitle,
  asMenu,
  ...externalInputProps
}: InlineAutocompleteProps & React.ComponentProps<'textarea' | 'input'>) => {
  const [, setScrollKey] = useState(0)

  const inputProps = useFormControlForwardedProps(externalInputProps)

  const inputRef = useRef<HTMLInputElement & HTMLTextAreaElement>(null)
  // @ts-expect-error children.ref can be a string because it's a legacy ref - this is probably incorrect
  useRefObjectAsForwardedRef(children.ref ?? noop, inputRef)

  const externalInput = requireChildrenToBeInput(children, inputRef)

  const emitSyntheticChange = useSyntheticChange({
    inputRef,
    fallbackEventHandler: externalInput.props.onChange ?? noop,
  })

  /** Stores the query that caused the current suggestion list to appear. */
  const showEventRef = useRef<ShowSuggestionsEvent | null>(null)

  const suggestionsVisible = suggestions !== null && suggestions.length > 0

  const [activeSuggestionKey, setActiveSuggestionKey] = useState<string>()
  const activeSuggestion = Array.isArray(suggestions)
    ? suggestions.find(s => getSuggestionKey(s) === activeSuggestionKey) ?? suggestions[0]
    : undefined

  if (activeSuggestionKey && !suggestionsVisible) setActiveSuggestionKey(undefined)

  useEffect(() => {
    if (suggestionsVisible) {
      const onScroll = throttle(() => setScrollKey(current => current + 1), 100)

      // eslint-disable-next-line github/prefer-observers
      document.addEventListener('scroll', onScroll, {capture: true})
      return () => {
        document.removeEventListener('scroll', onScroll, {capture: true})
      }
    }
  }, [suggestionsVisible])

  // The suggestions don't usually move while open, so it seems as though this could be
  // optimized by only re-rendering when suggestionsVisible changes. However, the user
  // could move the cursor to a different location using arrow keys and then type a
  // trigger, which would move the suggestions without closing/reopening them.
  const triggerCharCoords =
    inputRef.current && showEventRef.current && suggestionsVisible
      ? new InputRange(
          inputRef.current,
          (getSelectionStart(inputRef.current) ?? 0) - showEventRef.current.query.length,
        ).getBoundingClientRect()
      : {top: 0, left: 0, height: 0}

  // User can blur while suggestions are visible with shift+tab
  const onBlur: React.FocusEventHandler<TextInputElement> = () => {
    onHideSuggestions()
  }

  const navigate = (direction: 'up' | 'down' | 'start' | 'end') => {
    // Suggestions can be visible but not navigable when the the loading state is shown
    // The Array.isArray check is fully redundant but satisfies the typechecker
    if (!activeSuggestion || !Array.isArray(suggestions)) return

    const setActiveSuggestion = (suggestion: Suggestion | undefined) => {
      setActiveSuggestionKey(suggestion ? getSuggestionKey(suggestion) : undefined)
    }

    switch (direction) {
      case 'up':
        setActiveSuggestion(suggestions[suggestions.indexOf(activeSuggestion) - 1] ?? suggestions.at(-1))
        break
      case 'down':
        setActiveSuggestion(suggestions[suggestions.indexOf(activeSuggestion) + 1] ?? suggestions[0])
        break
      case 'start':
        setActiveSuggestion(suggestions[0])
        break
      case 'end':
        setActiveSuggestion(suggestions.at(-1))
        break
    }
  }

  const onKeyDown: React.KeyboardEventHandler<TextInputElement> = event => {
    if (!suggestionsVisible) return

    // We can't do _everything_ with ui-commands, unfortunately. In these cases we don't want to preventDefault and
    // they don't really make sense as commands anyway

    // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
    switch (event.key) {
      case 'ArrowRight':
      case 'ArrowLeft':
        onHideSuggestions()
        break
      case 'Tab':
        if (!tabInsertsSuggestions) {
          // onBlur will hide the suggestions too, but it will do it too late and focus will enter the overlay first,
          // which results in focus getting lost
          onHideSuggestions()
          break
        }
    }
  }

  const onChange: React.ChangeEventHandler<TextInputElement> = event => {
    const selectionStart = getSelectionStart(event.currentTarget)
    if (selectionStart === null) {
      onHideSuggestions()
      return
    }

    const query = calculateSuggestionsQuery(triggers, event.currentTarget.value, selectionStart)
    showEventRef.current = query && {
      ...query,
      target: event.currentTarget,
    }

    if (showEventRef.current) {
      onShowSuggestions(showEventRef.current)
    } else {
      onHideSuggestions()
    }
  }

  const onCommit = (suggestion = activeSuggestion) => {
    if (!suggestion) return

    const isMultistep = isNullSuggestion(suggestion)
    const value = getSuggestionValue(suggestion) ?? ''

    if (!inputRef.current || !showEventRef.current) return
    const {query, trigger} = showEventRef.current

    const currentCaretPosition = getSelectionStart(inputRef.current) ?? 0
    const deleteLength = query.length + trigger.triggerChar.length
    const startIndex = currentCaretPosition - deleteLength

    const keepTriggerChar = isMultistep || (trigger.keepTriggerCharOnCommit ?? true)
    const maybeTriggerChar = keepTriggerChar ? trigger.triggerChar : ''

    const insertSpace = !isMultistep && (trigger.insertSpaceOnCommit ?? true)
    const maybeSpace = insertSpace ? ' ' : ''

    const replacement = `${maybeTriggerChar}${value}${maybeSpace}`

    onHideSuggestions()
    emitSyntheticChange(replacement, [startIndex, startIndex + deleteLength])

    onSelectSuggestion?.({suggestion, trigger, query, target: inputRef.current})
  }

  const listId = useId()
  const getSuggestionId = (suggestion: Suggestion) => `${listId}-${getSuggestionKey(suggestion)}`

  const asCombobox = !asMenu

  // eslint-disable-next-line @eslint-react/no-clone-element
  const input = cloneElement(externalInput, {
    ...inputProps,
    onBlur: augmentHandler(externalInput.props.onBlur, onBlur),
    onKeyDownCapture: augmentHandler(externalInput.props.onKeyDownCapture, onKeyDown),
    onChange: augmentHandler(externalInput.props.onChange, onChange),
    ref: inputRef,
    role: suggestionsVisible && asCombobox ? 'combobox' : externalInput.props.role,
    ['aria-expanded']: suggestionsVisible && asCombobox ? 'true' : externalInput.props['aria-expanded'],
    ['aria-activedescendant']: activeSuggestion
      ? getSuggestionId(activeSuggestion)
      : externalInput.props['aria-activedescendant'],
    ['aria-controls']: suggestionsVisible && asCombobox ? listId : externalInput.props['aria-controls'],
    ['aria-owns']: suggestionsVisible && asMenu ? listId : externalInput.props['aria-owns'],
    ['aria-autocomplete']: suggestionsVisible && asCombobox ? 'list' : externalInput.props['aria-autocomplete'],
    ['aria-haspopup']: suggestionsVisible && asCombobox ? 'listbox' : externalInput.props['aria-haspopup'],
  })

  /**
   * Even though we apply all the aria attributes, screen readers don't fully support this
   * dynamic use case and so they don't have a native way to indicate to the user when
   * there are suggestions available. So we use some hidden text with aria-live to politely
   * indicate what's available and how to use it.
   *
   * This text should be consistent and the important info should be first, because users
   * will hear it as they type - if they have heard the message before they should be able
   * to recognize it and quickly apply the first suggestion without listening to the rest
   * of the message.
   *
   * When screen reader users navigate using arrow keys, the `aria-activedescendant` will
   * change and will be read out so we don't need to handle that interaction here.
   */
  const suggestionsDescription = !suggestionsVisible
    ? ''
    : suggestions === 'loading'
      ? 'Loading autocomplete suggestions…'
      : // It's important to include both Enter and Tab because we are telling the user that we are hijacking these keys:
        asCombobox
        ? `${suggestions.length} autocomplete ${
            suggestions.length === 1 ? 'suggestion' : 'suggestions'
          } available; "${getSuggestionValue(suggestions[0]!)}" is highlighted. Press ${
            tabInsertsSuggestions ? 'Enter or Tab' : 'Enter'
          } to select.`
        : ''

  return (
    // Using ui-commands for keybinding resolves conflicts with containing components that may also use ui-commands,
    // since ui-commands always takes priority. Otherwise, if a containing component binds an enter command, for example,
    // it will take priority over the inline autocomplete's enter command, which is not what we want
    <ScopedCommands
      commands={
        suggestionsVisible
          ? {
              // Even though the overlay has an Escape listener, it only works when focus is inside the overlay. In this
              // case, the textarea is focused, so we have to handle closing the overlay
              'github:cancel': () => onHideSuggestions(),
              'github:select': () => onCommit(),
              'github:focus-next': tabInsertsSuggestions ? () => onCommit() : undefined,
              'github:down': () => navigate('down'),
              'github:up': () => navigate('up'),
              'github:go-to-start': () => navigate('start'),
              'github:go-to-end': () => navigate('end'),
            }
          : {}
      }
      className={clsx(styles.container, fullWidth && styles.fullWidth)}
      style={style}
    >
      {input}
      {IS_BROWSER && (
        <AutocompleteSuggestions
          id={listId}
          suggestions={suggestions}
          inputRef={inputRef}
          onCommit={onCommit}
          onClose={onHideSuggestions}
          triggerCharCoords={triggerCharCoords}
          visible={suggestionsVisible}
          defaultPlacement={suggestionsPlacement}
          portalName={portalName}
          activeSuggestion={activeSuggestion}
          getSuggestionId={getSuggestionId}
          menuTitle={menuTitle}
          role={asMenu ? 'menu' : 'listbox'}
        />
      )}
      {IS_BROWSER && (
        <Portal>
          {/* This should NOT be linked to the input with aria-describedby or screen readers may not read the live updates.
        The assertive live attribute ensures the suggestions are read instead of the input label, which voiceover will try to re-read when the role changes. */}
          <span aria-live="assertive" aria-atomic style={{clipPath: 'circle(0)', position: 'absolute'}}>
            {suggestionsDescription}
          </span>
        </Portal>
      )}
    </ScopedCommands>
  )
}

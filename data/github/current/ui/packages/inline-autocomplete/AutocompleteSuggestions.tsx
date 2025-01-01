import {ActionList, type ActionListItemProps, Overlay, useIsomorphicLayoutEffect} from '@primer/react'
import {SkeletonText} from '@primer/react/experimental'
import type React from 'react'
import {useId, useRef, useState} from 'react'

import styles from './AutocompleteSuggestions.module.css'
import type {Suggestion, Suggestions, SuggestionsPlacement, TextInputElement} from './types'
import {getSuggestionKey, getSuggestionValue} from './utils'

type AutoCompleteSuggestionsProps = {
  suggestions: Suggestions | null
  activeSuggestion?: Suggestion
  portalName?: string
  triggerCharCoords: {top: number; left: number; height: number}
  onClose: () => void
  onCommit: (suggestion: Suggestion) => void
  inputRef: React.RefObject<TextInputElement>
  visible: boolean
  defaultPlacement: SuggestionsPlacement
  getSuggestionId: (suggestion: Suggestion) => string
  id: string
  menuTitle?: string
  role: 'menu' | 'listbox'
}

const LoadingIndicator = () => (
  <>
    <ActionList.Item disabled>
      <SkeletonText />
    </ActionList.Item>
    <ActionList.Item disabled>
      <SkeletonText />
    </ActionList.Item>
    <ActionList.Item disabled>
      <SkeletonText />
    </ActionList.Item>
  </>
)

const SuggestionListItem = ({
  suggestion,
  onSelect,
  isActive,
  id,
  parentRole,
}: {
  suggestion: Suggestion
  onSelect: () => void
  isActive: boolean
  id: string
  parentRole: 'menu' | 'listbox'
}) => {
  const value = getSuggestionValue(suggestion)

  const sharedProps: React.LiHTMLAttributes<HTMLLIElement> & ActionListItemProps = {
    id,
    children: value,
    role: parentRole === 'menu' ? 'menuitem' : 'option',
    active: isActive,
    className: styles.suggestion,
    ['aria-selected']: parentRole === 'listbox' && isActive ? true : undefined,
    // onSelect/onClick won't work here; we want sto prevent default before focus leaves the input, so that focus remains
    // on the input. We don't need to handle key events here since that's done at the input level.
    onMouseDown: event => {
      event.preventDefault()
      onSelect()
    },
  }

  return typeof suggestion === 'string' ? <ActionList.Item {...sharedProps} /> : suggestion.render(sharedProps)
}

/**
 * Renders an overlayed list at the given relative coordinates. Handles keyboard navigation
 * and accessibility concerns.
 */
const AutocompleteSuggestions = ({
  suggestions,
  portalName,
  triggerCharCoords,
  onClose,
  onCommit,
  inputRef,
  visible,
  defaultPlacement,
  activeSuggestion,
  getSuggestionId,
  id,
  menuTitle,
  role,
}: AutoCompleteSuggestionsProps) => {
  const overlayRef = useRef<HTMLDivElement | null>(null)

  const [top, setTop] = useState(0)
  useIsomorphicLayoutEffect(
    function recalculateTop() {
      const overlayHeight = overlayRef.current?.offsetHeight ?? 0

      const belowOffset = triggerCharCoords.top + triggerCharCoords.height
      const wouldOverflowBelow = belowOffset + overlayHeight > window.innerHeight

      const aboveOffset = triggerCharCoords.top - overlayHeight
      const wouldOverflowAbove = aboveOffset < 0

      // Only override the default if it would overflow in the default direction and it would not overflow in the override direction
      const result = {
        below: wouldOverflowBelow && !wouldOverflowAbove ? aboveOffset : belowOffset,
        above: wouldOverflowAbove && !wouldOverflowBelow ? belowOffset : aboveOffset,
      }[defaultPlacement]

      // Sometimes the value can be NaN if layout is not available (ie, SSR or JSDOM)
      const resultNotNaN = Number.isNaN(result) ? 0 : result

      setTop(resultNotNaN)
    },
    // this is a cheap effect and we want it to run when pretty much anything that could affect position changes
    [triggerCharCoords.top, triggerCharCoords.height, suggestions, visible, defaultPlacement],
  )

  const items = (
    <>
      {suggestions === 'loading' ? (
        <LoadingIndicator />
      ) : (
        suggestions?.map(suggestion => (
          <SuggestionListItem
            suggestion={suggestion}
            key={getSuggestionKey(suggestion)}
            id={getSuggestionId(suggestion)}
            onSelect={() => onCommit(suggestion)}
            isActive={activeSuggestion === suggestion}
            parentRole={role}
          />
        ))
      )}
    </>
  )
  const labelId = useId()

  // Conditional rendering appears wrong at first - it means that we are reconstructing the
  // Combobox instance every time the suggestions appear. But this is what we want - otherwise
  // the textarea would always have the `combobox` role, which is incorrect (a textarea should
  // not technically ever be a combobox). We compromise by dynamically applying the combobox
  // role only when suggestions are available.
  return visible ? (
    <Overlay
      onEscape={onClose}
      onClickOutside={onClose}
      returnFocusRef={inputRef}
      preventFocusOnOpen
      portalContainerName={portalName}
      top={top}
      left={triggerCharCoords.left}
      ref={overlayRef}
      className={styles.Overlay_0}
    >
      <ActionList
        role={role}
        id={id}
        aria-label={menuTitle ? undefined : 'Autocomplete suggestions'}
        aria-labelledby={menuTitle ? labelId : undefined}
      >
        {menuTitle ? (
          <ActionList.Group>
            <ActionList.GroupHeading id={labelId}>{menuTitle}</ActionList.GroupHeading>
            {items}
          </ActionList.Group>
        ) : (
          items
        )}
      </ActionList>
    </Overlay>
  ) : (
    <></>
  )
}

export default AutocompleteSuggestions

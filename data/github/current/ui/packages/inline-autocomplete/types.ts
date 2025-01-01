import type {ActionListItemProps} from '@primer/react'

export type Trigger = {
  /** A single character that can cause the suggestion list to open. */
  triggerChar: string
  /**
   * Control whether the suggestion query can contain spaces. This should *not* be `true` if
   * `triggerChar` is a space.
   * @default false
   */
  multiWord?: boolean
  /**
   * Control whether the trigger character is retained when inserting a suggestion.
   * @default true
   */
  keepTriggerCharOnCommit?: boolean
  /**
   * Control whether a space is inserted after the value when inserting a suggestion.
   * @default true
   */
  insertSpaceOnCommit?: boolean
}

export type SelectSuggestionsEvent = ShowSuggestionsEvent & {
  /** The suggestion that was selected. */
  suggestion: Suggestion
}

export type ShowSuggestionsEvent = {
  /** The trigger that caused this query. */
  trigger: Trigger
  /** The query string. */
  query: string
  /** The input element. */
  target: TextInputElement
}

/**
 * Renders a suggestion that will not insert text into the input, but _will_ clear the filter text. Null suggestions
 * can be used for multi-step menus (be sure to also render `aria-haspopup` and a caret indicator on the item!) or
 * suggestions that perform side-effects like opening links.
 *
 * If any null suggestions are used in the menu, the `asMenu` prop should be set on `InlineAutocomplete` to provide
 * better accessibility semantics for complex autocomplete menus.
 */
export type NullSuggestion = {
  /** For null suggections, `value` is always `null`. */
  value: null
  /** Because there is no `value`, a `key` is required for null suggestions. */
  key: string
  /** This must return an `ActionList.Item` instance. */
  render: (props: ActionListItemProps) => React.ReactElement
}

export type Suggestion =
  | string
  | {
      /**
       * The plain text value of the suggestion. This is the text that will be inserted when
       * the user applies the suggestion. If no `key` is provided, this value **must** be unique
       * across all currently visible suggestions.
       */
      value: string
      /**
       * Optional key. If not provided, the `value` will be used. Setting a `key` allows
       * for non-unique `value`s.
       */
      key?: string
      /** This must return an `ActionList.Item` instance. */
      render: (props: ActionListItemProps) => React.ReactElement
    }
  | NullSuggestion

export type Suggestions = Suggestion[] | 'loading'

export type TextInputElement = HTMLInputElement | HTMLTextAreaElement

export type TextInputCompatibleChild = React.ReactElement<
  JSX.IntrinsicElements['textarea'] | JSX.IntrinsicElements['input']
> &
  React.RefAttributes<HTMLInputElement & HTMLTextAreaElement>

export type SuggestionsPlacement = 'above' | 'below'

export type TriggerAndSuggestions = {
  trigger: Trigger
  suggestionsCalculator: (query: string) => Promise<Suggestions>
}

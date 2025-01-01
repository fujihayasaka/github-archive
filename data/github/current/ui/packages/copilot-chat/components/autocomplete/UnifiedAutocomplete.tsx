import {sendEvent} from '@github-ui/hydro-analytics'
import {InlineAutocomplete} from '@github-ui/inline-autocomplete'
import type {SelectSuggestionsEvent, ShowSuggestionsEvent, Trigger} from '@github-ui/inline-autocomplete/types'
import type {DetailedHTMLProps, InputHTMLAttributes, ReactElement} from 'react'
import {useEffect, useState} from 'react'

import {useChatState} from '../../utils/CopilotChatContext'
import {ReferenceMention} from '../../utils/reference-mention'
import {categoryNames, CategoryValue} from './categories'
import {useAutocompleteAgentsDialogs} from './use-autocomplete-agents-dialogs'
import {type AutocompleteQuery, useAutocompleteSuggestions} from './useAutocompleteSuggestions'

const triggers: Trigger[] = [
  {triggerChar: '@', insertSpaceOnCommit: true, keepTriggerCharOnCommit: false, multiWord: true},
]

/** Returns a blank query corresponding to the selected category. */
function selectedCategoryQuery(category: CategoryValue): AutocompleteQuery {
  switch (category) {
    case 'repositories':
      return {category: 'repositories', filter: ''}
    case 'agents':
      return {category: 'agents', filter: ''}
    case 'repositories:discussions':
      return {category: 'repositories', filter: '', nextCategory: 'discussions'}
    case 'repositories:issues':
      return {category: 'repositories', filter: '', nextCategory: 'issues'}
    case 'repositories:pulls':
      return {category: 'repositories', filter: '', nextCategory: 'pulls'}
    case 'repositories:files':
      return {category: 'repositories', filter: '', nextCategory: 'files'}
  }
}

// null return ensures we get completeness detection from the typechecker because undefined is not allowed to be returned
function getTitleForQuery(query: AutocompleteQuery): string | null {
  switch (query.category) {
    case 'categories':
      return null
    case 'repositories':
      switch (query.nextCategory) {
        case 'discussions':
        case 'issues':
        case 'pulls':
        case 'files':
          return `${categoryNames[query.nextCategory]} ›`
        default:
          return 'Repositories ›'
      }
    case 'agents':
      return categoryNames[query.category]
    case 'discussions':
    case 'issues':
    case 'pulls':
    case 'files':
      return `${categoryNames[query.category]} › ${query.repository} ›`
    case 'sso-orgs':
      return 'Single sign-on'
  }
}

export interface UnifiedAutocompleteProps {
  children: ReactElement<DetailedHTMLProps<InputHTMLAttributes<HTMLTextAreaElement>, HTMLTextAreaElement>>
  onSelectReference: (ReferenceMention: ReferenceMention) => void
  onShowAgentsDialog: (dialog: 'no-agents-available' | 'agents-not-supported') => void
}

export function UnifiedAutocomplete({children, onSelectReference, onShowAgentsDialog}: UnifiedAutocompleteProps) {
  const {mode} = useChatState()

  const [mounted, setMounted] = useState(() => typeof document !== 'undefined')
  useEffect(() => setMounted(true), [])

  const [query, setQuery] = useState<AutocompleteQuery | null>(null)
  const {suggestions, stale: suggestionsDataStale} = useAutocompleteSuggestions(query)

  useAutocompleteAgentsDialogs({query, onShowAgentsDialog})

  if (!mounted) return <div>{children}</div>

  const onSelectSuggestion = ({suggestion}: SelectSuggestionsEvent) => {
    const suggestionValue = typeof suggestion === 'string' ? suggestion : suggestion.value
    sendEvent('dotcom_chat.activate', {
      target: 'AUTOCOMPLETE_ITEM_SELECTED',
      mode,
      suggestion: suggestionValue,
    })

    const mention =
      suggestionValue !== null && query?.category !== 'agents' ? ReferenceMention.parse(suggestionValue) : undefined
    if (mention) onSelectReference(mention)

    // Reopen the menu for multistep queries
    const isMultistepSuggestion = typeof suggestion === 'object' && suggestion.value === null
    if (!isMultistepSuggestion) return

    // Hack that allows us to put the Extensions marketplace link into the menu
    const openLinkMatch = /^open-link:(.+)$/.exec(suggestion.key)
    if (openLinkMatch) {
      setQuery(null)
      window.open(openLinkMatch[1], '_blank')
      return
    }

    switch (query?.category) {
      case 'categories':
        if (CategoryValue.is(suggestion.key)) setQuery(selectedCategoryQuery(suggestion.key))
        break
      case 'repositories':
        if (suggestion.key === 'sso-orgs') setQuery({category: 'sso-orgs', filter: ''})
        else if (query.nextCategory) setQuery({category: query.nextCategory, filter: '', repository: suggestion.key})
        break
    }
  }

  const onShowSuggestions = (event: ShowSuggestionsEvent) =>
    setQuery(q =>
      q
        ? {...q, filter: event.query}
        : {
            category: 'categories',
            filter: event.query,
            index: (event.target.selectionStart ?? 0) - (event.query.length + event.trigger.triggerChar.length),
          },
    )

  const onHideSuggestions = () => setQuery(null)

  return (
    <>
      <InlineAutocomplete
        fullWidth
        suggestions={suggestions}
        triggers={triggers}
        tabInsertsSuggestions={false}
        onHideSuggestions={onHideSuggestions}
        onShowSuggestions={onShowSuggestions}
        onSelectSuggestion={onSelectSuggestion}
        suggestionsPlacement="above"
        title={(query && getTitleForQuery(query)) || undefined}
        asMenu
      >
        {children}
      </InlineAutocomplete>
      {suggestionsDataStale && (
        <span role="status" aria-live="polite" className="sr-only">
          Loading
        </span>
      )}
    </>
  )
}

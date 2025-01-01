import {useEffect} from 'react'

import {useAvailableAgents} from '../../utils/agents-helpers'
import type {AutocompleteQuery} from './useAutocompleteSuggestions'

interface AutocompleteAgentsDialogsProps {
  query: AutocompleteQuery | null
  onShowAgentsDialog: (dialog: 'no-agents-available' | 'agents-not-supported') => void
}

/**
 * Handles opening the appropriate agents dialog when required.
 */
export function useAutocompleteAgentsDialogs({query, onShowAgentsDialog}: AutocompleteAgentsDialogsProps) {
  const active = query?.category === 'agents'
  const {availableAgents, loading, disabled} = useAvailableAgents(active)

  useEffect(() => {
    if (!active || loading) return

    if (disabled) onShowAgentsDialog('agents-not-supported')
    else if (!availableAgents?.length) onShowAgentsDialog('no-agents-available')
  }, [active, loading, availableAgents, disabled, onShowAgentsDialog])
}

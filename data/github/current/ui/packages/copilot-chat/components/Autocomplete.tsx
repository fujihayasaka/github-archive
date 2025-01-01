import {copilotFeatureFlags} from '../utils/copilot-feature-flags'
import {AgentAutocomplete} from './autocomplete/AgentAutocomplete'
import {UnifiedAutocomplete, type UnifiedAutocompleteProps} from './autocomplete/UnifiedAutocomplete'

export function Autocomplete({children, onSelectReference, onShowAgentsDialog}: UnifiedAutocompleteProps) {
  return copilotFeatureFlags.chatAutocomplete ? (
    <UnifiedAutocomplete onSelectReference={onSelectReference} onShowAgentsDialog={onShowAgentsDialog}>
      {children}
    </UnifiedAutocomplete>
  ) : (
    <AgentAutocomplete>{children}</AgentAutocomplete>
  )
}

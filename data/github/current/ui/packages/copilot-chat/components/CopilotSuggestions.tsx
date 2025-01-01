import {sendEvent} from '@github-ui/hydro-analytics'
import {PaperAirplaneIcon} from '@primer/octicons-react'
import {ActionList} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {memo, useCallback} from 'react'

import type {GeneratedSuggestion} from '../utils/copilot-chat-types'
import {copilotFeatureFlags} from '../utils/copilot-feature-flags'
import {useChatState} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'

const CopilotSuggestions = ({suggestionKind}: {suggestionKind?: string}) => {
  const state = useChatState()
  const manager = useChatManager()

  const onClickSuggestion = useCallback(
    (suggestion: GeneratedSuggestion) => {
      void manager.sendChatMessage({
        thread: manager.getSelectedThread(state),
        content: suggestion.prompt ?? suggestion.question,
        intent: suggestion.intent,
        modeOverride: suggestion.mode,
        references: state.currentReferences,
        topic: state.currentTopic,
        context: state.context,
      })

      sendEvent('copilot_generated_suggestion_click', {
        intent: suggestion.intent,
        mode: suggestion.mode,
        contextType: state.context?.[0]?.type,
        content: suggestion.question,
      })
    },
    [manager, state],
  )
  const CopilotSuggestion = memo(function CopilotSuggestion({suggestion}: {suggestion: GeneratedSuggestion}) {
    return (
      <ActionList.Item
        onSelect={() => onClickSuggestion(suggestion)}
        sx={{
          mx: 0,
          border: '1px solid',
          borderColor: 'border.default',
          width: 'fit-content',
        }}
      >
        <ActionList.LeadingVisual>
          <Octicon icon={PaperAirplaneIcon} />
        </ActionList.LeadingVisual>
        <span> {suggestion.question}</span>
      </ActionList.Item>
    )
  })

  const isLoading = state.messagesLoading.state === 'loading' || !!state.streamingMessage
  const {suggestions} = state

  const firstReference = state.currentReferences[0]
  const onlyReferenceIsCurrentRepo =
    state.currentReferences.length === 1 &&
    firstReference?.type === 'repository' &&
    firstReference.id === state.currentRepository?.id

  const showCopilotSuggestions = Boolean(
    !isLoading &&
      (copilotFeatureFlags.topicsAsReferences
        ? onlyReferenceIsCurrentRepo
        : !state.showTopicPicker && state.currentReferences.length === 0),
  )
  return showCopilotSuggestions && !!suggestions && !!suggestions.suggestions ? (
    <ActionList className="copilot-suggestions" sx={{pt: 0, pb: 3, display: 'flex', gap: 2, flexDirection: 'column'}}>
      {suggestionKind === 'initial' && (
        <ActionList.Heading as="h2" sx={{fontSize: 0, mx: 0, color: 'fg.muted', fontWeight: 600}}>
          {suggestionHeadingForReferenceType(suggestions.referenceType as string)}
        </ActionList.Heading>
      )}
      {suggestions?.suggestions.map(s => <CopilotSuggestion key={s.question} suggestion={s} />)}
    </ActionList>
  ) : null
}

function suggestionHeadingForReferenceType(referenceType?: string): string {
  if (!referenceType) return 'Ask anything:'
  return `Ask about the ${referenceType.replace(/-/g, ' ')}:`
}

export default memo(CopilotSuggestions)

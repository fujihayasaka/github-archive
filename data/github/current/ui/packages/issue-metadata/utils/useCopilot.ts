// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {useCallback} from 'react'
import type RelayModernEnvironment from 'relay-runtime/lib/store/RelayModernEnvironment'
import {useIssueLabelSuggestions} from '../hooks/useIssueLabelSuggestions'
import {useIssueTypeSuggestions} from '../hooks/useIssueTypeSuggestions'
import type {CopilotRequestStatus} from '../utils/copilot-utils'

/**
 * Main hook that provides Copilot suggestions for both issue types and labels
 */
export function useCopilot() {
  const {getSuggestion: getTypeSuggestion, status: typeStatus, suggestedType} = useIssueTypeSuggestions()

  const {getSuggestions: getLabelSuggestions, status: labelsStatus, suggestedLabels} = useIssueLabelSuggestions()

  /**
   * Get suggestions based on the requested type
   */
  const getSuggestions = useCallback(
    ({
      issueId,
      environment,
      type,
      issueTitle,
      issueBody,
      repositoryName,
      repositoryOwner,
    }: {
      issueId: string
      environment: RelayModernEnvironment
      type?: 'labels' | 'issueType'
      issueTitle?: string
      issueBody?: string
      repositoryName?: string
      repositoryOwner?: string
    }) => {
      if (type === 'issueType') {
        getTypeSuggestion({issueId, environment})
      } else {
        getLabelSuggestions({issueId, environment, issueTitle, issueBody, repositoryName, repositoryOwner})
      }
    },
    [getTypeSuggestion, getLabelSuggestions],
  )

  /**
   * Get the status for a specific suggestion type
   */
  const getStatusForType = (type: 'labels' | 'issueType'): CopilotRequestStatus => {
    return type === 'issueType' ? typeStatus : labelsStatus
  }

  return {
    // Main API for combined functionality
    getSuggestions,
    getStatusForType,
    suggestedLabels,
    suggestedType,

    // Direct access to specialized hooks when needed
    getTypeSuggestion,
    getLabelSuggestions,
    typeStatus,
    labelsStatus,
  }
}

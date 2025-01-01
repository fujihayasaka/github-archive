// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {IssueTypeFragment} from '@github-ui/item-picker/IssueTypePicker'
import type {
  IssueTypePickerIssueType$data,
  IssueTypePickerIssueType$key,
} from '@github-ui/item-picker/IssueTypePickerIssueType.graphql'
import {useCallback, useState} from 'react'
import {fetchQuery, graphql, readInlineData} from 'relay-runtime'
import type RelayModernEnvironment from 'relay-runtime/lib/store/RelayModernEnvironment'
import {issueTypePrompt} from '../constants/copilot'
import type {CopilotRequestStatus} from '../utils/copilot-utils'
import {createCopilotRequest, useCopilotAuth} from '../utils/copilot-utils'
import type {useIssueTypeSuggestionsQuery} from './__generated__/useIssueTypeSuggestionsQuery.graphql'

// GraphQL query specifically for issue type data
const issueTypeQuery = graphql`
  query useIssueTypeSuggestionsQuery($issueId: ID!) {
    node(id: $issueId) {
      ... on Issue {
        body
        title
        repository {
          issueTypes(first: 100) {
            nodes {
              ...IssueTypePickerIssueType
            }
          }
        }
      }
    }
  }
`

/**
 * Hook for getting Copilot suggestions for issue types
 */
export function useIssueTypeSuggestions() {
  const authProvider = useCopilotAuth()
  const [status, setStatus] = useState<CopilotRequestStatus>('loading')
  const [suggestedType, setSuggestedType] = useState<IssueTypePickerIssueType$data | undefined>(undefined)

  /**
   * Request issue type suggestions from Copilot
   */
  const requestTypeSuggestion = useCallback(
    async ({
      issueId,
      title,
      body,
      availableTypes,
    }: {
      issueId: string
      title: string | undefined
      body: string | undefined
      availableTypes: IssueTypePickerIssueType$data[]
    }) => {
      try {
        const token = await authProvider.current.getAuthToken()

        // Create references for the Copilot API
        const references = [
          {
            id: issueId,
            data: {
              title,
              body,
            },
          },
        ]

        // Generate prompt with available issue types
        const prompt = issueTypePrompt(availableTypes.map(t => t.name).join(', '))

        // Make the request to Copilot API
        const result = await createCopilotRequest(token, prompt, references)

        if (result) {
          // Check if result object has any keys before attempting to reduce
          const resultKeys = Object.keys(result)

          if (resultKeys.length === 0) {
            setSuggestedType(undefined)
            setStatus('success') // Still considered a success if no types are suggested
            return
          }

          // Identify the issue type with highest confidence
          const highestConfidenceType = resultKeys.reduce((a, b) => (result[a] > result[b] ? a : b), '')

          // Find the matching type in our available options
          const matchingType = availableTypes.find(t => highestConfidenceType === t.name)

          setSuggestedType(matchingType)
          setStatus('success')
        } else {
          setStatus('error')
        }
      } catch {
        setStatus('error')
      }
    },
    [authProvider],
  )

  /**
   * Fetch issue data and get type suggestions from Copilot
   */
  const getSuggestion = useCallback(
    ({issueId, environment}: {issueId: string; environment: RelayModernEnvironment}) => {
      setStatus('loading')

      fetchQuery<useIssueTypeSuggestionsQuery>(environment, issueTypeQuery, {
        issueId,
      }).subscribe({
        next: data => {
          // Set initial loading state for screen readers
          setStatus('loading')

          if (!data.node || !('repository' in data.node)) {
            setStatus('error')
            return
          }

          const {body, title, repository} = data.node
          if (!repository?.issueTypes) {
            setStatus('error')
            return
          }

          // Extract available issue types
          const availableTypes =
            repository.issueTypes.nodes?.flatMap(edge => {
              // Use type guard to ensure edge is valid and matches expected structure
              if (edge && typeof edge === 'object') {
                return [
                  // eslint-disable-next-line no-restricted-syntax
                  readInlineData<IssueTypePickerIssueType$key>(IssueTypeFragment, edge as IssueTypePickerIssueType$key),
                ]
              }
              return []
            }) || []

          // Request type suggestion if we have available types
          if (availableTypes.length > 0) {
            requestTypeSuggestion({issueId, title, body, availableTypes})
          } else {
            setStatus('error')
          }
        },
        error: () => {
          setStatus('error')
        },
      })
    },
    [requestTypeSuggestion],
  )

  return {
    getSuggestion,
    status,
    suggestedType,
  }
}

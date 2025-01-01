// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import type {LabelPickerLabel$data} from '@github-ui/item-picker/LabelPickerLabel.graphql'
import {repositoryPath} from '@github-ui/paths'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {useCallback, useEffect, useMemo, useRef, useState} from 'react'
import type RelayModernEnvironment from 'relay-runtime/lib/store/RelayModernEnvironment'
import {labelsPrompt} from '../constants/copilot'
import type {CopilotRequestStatus} from '../utils/copilot-utils'
import {createCopilotRequest, useCopilotAuth} from '../utils/copilot-utils'
import {isTracingEnabled, reportTraceData} from '@github-ui/internal-api-insights'

// Minimum confidence threshold for label suggestions (95%)
const CONFIDENCE_THRESHOLD = 80

type IssueData = {
  issueId: string
  issueTitle?: string
  issueBody?: string
  repositoryName?: string
  repositoryOwner?: string
}

/**
 * Hook for getting Copilot suggestions for issue labels
 */
export function useIssueLabelSuggestions() {
  const authProvider = useCopilotAuth()
  const [status, setStatus] = useState<CopilotRequestStatus>('loading')
  const [suggestedLabels, setSuggestedLabels] = useState<LabelPickerLabel$data[]>([])

  // Store issue data in a ref to avoid unnecessary rerenders
  const issueDataRef = useRef<IssueData>({
    issueId: '',
    issueTitle: undefined,
    issueBody: undefined,
    repositoryName: undefined,
    repositoryOwner: undefined,
  })

  // Track if the component is mounted to avoid state updates after unmounting
  const isMountedRef = useRef(true)

  /**
   * Request label suggestions from Copilot
   */
  const requestLabelSuggestions = useCallback(
    async (availableLabels: LabelPickerLabel$data[]) => {
      try {
        const token = await authProvider.current.getAuthToken()
        const {issueId, issueTitle, issueBody} = issueDataRef.current

        if (!issueId) {
          setStatus('error')
          return
        }

        // Create references for the Copilot API with issue labels
        const references = [
          {
            id: issueId,
            type: 'github.issue',
            data: {
              type: 'issue',
              title: issueTitle,
              body: issueBody,
              labels: availableLabels.map(label => ({
                name: label.name,
                description: label.description,
              })),
            },
          },
        ]

        // Make the request to Copilot API
        const result = await createCopilotRequest(token, labelsPrompt, references)

        if (result) {
          // Filter labels with confidence level >= threshold
          const highConfidenceLabels = Object.keys(result).filter(key => result[key] >= CONFIDENCE_THRESHOLD)

          // Find matching labels from our available options
          const matchingLabels = availableLabels.filter(label => highConfidenceLabels.includes(label.name))

          setSuggestedLabels(matchingLabels)
          setStatus('success')
        } else {
          setSuggestedLabels([])
          setStatus('error')
        }
        // eslint-disable-next-line unused-imports/no-unused-vars
      } catch (error) {
        setStatus('error')
      }
    },
    [authProvider],
  )

  const fetchLabels = useCallback(async () => {
    if (!isMountedRef.current) return

    const {repositoryName, repositoryOwner} = issueDataRef.current

    if (!repositoryName || !repositoryOwner) {
      // If no repository name or owner is provided, reset the status
      setSuggestedLabels([])
      setStatus('idle')
      return
    }

    const repoPath = `${repositoryPath({owner: repositoryOwner, repo: repositoryName})}/label_recommendations.json`
    setStatus('loading')

    try {
      const url = new URL(repoPath, window.location.origin)
      const tracingEnabled = isTracingEnabled()
      if (tracingEnabled) {
        url.searchParams.append('_tracing', 'true')
      }

      const response = await verifiedFetchJSON(url.toString(), {
        method: 'GET',
      })

      if (!response.ok) {
        setStatus('error')
        return
      }

      const data = await response.json()

      if (tracingEnabled) {
        reportTraceData(data)
      }

      const labels = data.labels.map((label: LabelPickerLabel$data) => ({
        id: label.id,
        name: label.name,
        description: label.description,
        url: label.url,
        color: label.color,
        nameHTML: label.nameHTML,
      }))

      if (labels.length > 0) {
        await requestLabelSuggestions(labels)
      } else {
        setSuggestedLabels([])
        setStatus('success')
      }
      // eslint-disable-next-line unused-imports/no-unused-vars
    } catch (error) {
      setStatus('error')
    }
  }, [requestLabelSuggestions])

  // Reset component on unmount
  useEffect(() => {
    return () => {
      isMountedRef.current = false
    }
  }, [])

  /**
   * Fetch issue data and get label suggestions from Copilot
   */
  const getSuggestions = useCallback(
    ({
      issueId,
      issueTitle,
      issueBody,
      repositoryName,
      repositoryOwner,
    }: {
      issueId: string
      environment?: RelayModernEnvironment
      issueTitle?: string
      issueBody?: string
      repositoryName?: string
      repositoryOwner?: string
    }) => {
      if (!issueId) return

      // Update issue data ref without triggering rerenders
      issueDataRef.current = {
        issueId,
        issueTitle: issueTitle || issueDataRef.current.issueTitle,
        issueBody: issueBody || issueDataRef.current.issueBody,
        repositoryName: repositoryName || issueDataRef.current.repositoryName,
        repositoryOwner: repositoryOwner || issueDataRef.current.repositoryOwner,
      }

      fetchLabels()
    },
    [fetchLabels],
  )

  // Memoize return values to prevent unnecessary re-renders
  return useMemo(
    () => ({
      getSuggestions,
      status,
      suggestedLabels,
    }),
    [getSuggestions, status, suggestedLabels],
  )
}

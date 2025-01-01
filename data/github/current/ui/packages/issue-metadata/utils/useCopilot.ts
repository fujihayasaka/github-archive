// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {useCallback, useRef, useState} from 'react'
import {CopilotAuthTokenProvider} from '@github-ui/copilot-auth-token'
import type {
  IssueTypePickerIssueType$data,
  IssueTypePickerIssueType$key,
} from '@github-ui/item-picker/IssueTypePickerIssueType.graphql'
import type {LabelPickerLabel$data, LabelPickerLabel$key} from '@github-ui/item-picker/LabelPickerLabel.graphql'
import {useSafeAsyncCallback} from '@github-ui/use-safe-async-callback'
import {fetchQuery, graphql, readInlineData} from 'relay-runtime'
import type RelayModernEnvironment from 'relay-runtime/lib/store/RelayModernEnvironment'
import type {useCopilotFetchIssueDataQuery} from './__generated__/useCopilotFetchIssueDataQuery.graphql'
import {IssueTypeFragment} from '@github-ui/item-picker/IssueTypePicker'
import {LabelFragment} from '@github-ui/item-picker/LabelPicker'
import {issueTypePrompt, labelsPrompt} from '../constants/copilot'

const copilotFetchIssueDataQuery = graphql`
  query useCopilotFetchIssueDataQuery(
    $issueId: ID!
    $fetchAllTypes: Boolean = false
    $fetchAllLabels: Boolean = false
  ) {
    node(id: $issueId) {
      ... on Issue {
        body
        title
        repository {
          issueTypes(first: 10) @include(if: $fetchAllTypes) {
            nodes {
              ...IssueTypePickerIssueType
            }
          }
          allLabels: labels(first: 100) @include(if: $fetchAllLabels) {
            nodes {
              ...LabelPickerLabel
            }
          }
        }
      }
    }
  }
`

// Custom hook to use Copilot functionality
export const useCopilot = () => {
  const authTokenProvider = useRef(new CopilotAuthTokenProvider([]))
  const [copilotRequestSuccess, setCopilotRequestSuccess] = useState<'success' | 'error' | 'loading'>('loading')
  const [copilotLabels, setCopilotLabels] = useState<LabelPickerLabel$data[]>([])
  const [copilotType, setCopilotType] = useState<IssueTypePickerIssueType$data>()

  // Simple fetch to make a request to Copilot API with the given issue data
  const makeCopilotRequest = useSafeAsyncCallback(
    async ({
      issueId,
      title,
      body,
      type,
      labels,
      types,
    }: {
      issueId: string
      title: string | undefined
      body: string | undefined
      type: 'labels' | 'issueType'
      labels?: LabelPickerLabel$data[]
      types?: IssueTypePickerIssueType$data[]
    }) => {
      try {
        const token = await authTokenProvider.current.getAuthToken()
        const requestPath = 'https://api.githubcopilot.com/agents/github-classifier' // default request path for Copilot API classifier agent
        const copilot_references =
          type === 'issueType'
            ? [
                {
                  id: issueId,
                  data: {
                    title,
                    body,
                  },
                },
              ]
            : [
                {
                  id: issueId,
                  type: 'github.issue',
                  data: {
                    type: 'issue',
                    title,
                    body,
                    labels: labels?.map(l => {
                      return {name: l.name, description: l.description}
                    }),
                  },
                },
              ]

        const headers: {[key: string]: string} = {
          Authorization: token.authorizationHeaderValue,
          'copilot-integration-id': 'copilot-embedded-experience',
          'Content-Type': 'application/json',
        }

        const requestBody = {
          messages: [
            {
              role: 'user',
              content: type === 'issueType' ? issueTypePrompt(types?.map(t => t.name).join(', ')) : labelsPrompt,
              copilot_references,
            },
          ],
        }

        const result = await fetch(requestPath, {
          method: 'POST',
          mode: 'cors',
          cache: 'no-cache',
          headers,
          body: JSON.stringify(requestBody),
        })

        if (result.ok) {
          // Parse the response and extract the classification results
          const res = (await result.text()).split('\n')[0]?.substring(6)
          if (res) {
            // Parse the classification result in JSON format for easier use
            const resultJson = JSON.parse(JSON.parse(res).choices[0].message.content)
            if (type === 'issueType') {
              // pick the issue type with the highest confidence
              const highestConfidenceType = Object.keys(resultJson).reduce((a, b) =>
                resultJson[a] > resultJson[b] ? a : b,
              )
              const matchingType = types?.find(t => highestConfidenceType === t.name)
              if (matchingType) {
                setCopilotType?.(matchingType)
              }
            } else {
              // Filter labels with confidence level >= 95
              const highConfidenceLabels = Object.keys(resultJson).filter(key => resultJson[key] >= 95)
              const matchingData = labels?.filter(label => highConfidenceLabels.includes(label.name))
              if (matchingData && matchingData.length > 0) {
                setCopilotLabels?.(matchingData)
              }
            }
          }
          setCopilotRequestSuccess('success')
        } else {
          setCopilotRequestSuccess('error')
        }
      } catch {
        setCopilotRequestSuccess('error')
      }
    },
  )

  const fetchSuggestions = useCallback(
    ({
      issueId,
      environment,
      type,
    }: {
      issueId: string
      environment: RelayModernEnvironment
      type: 'labels' | 'issueType'
    }) => {
      fetchQuery<useCopilotFetchIssueDataQuery>(environment, copilotFetchIssueDataQuery, {
        issueId,
        fetchAllTypes: type === 'issueType',
        fetchAllLabels: type === 'labels',
      }).subscribe({
        next: data => {
          setCopilotRequestSuccess('loading')
          if (data.node && data.node.repository) {
            const {body, title, repository} = data.node
            const {issueTypes, allLabels} = repository
            const repoTypes =
              issueTypes?.nodes?.flatMap(edge =>
                // eslint-disable-next-line no-restricted-syntax
                edge ? [readInlineData<IssueTypePickerIssueType$key>(IssueTypeFragment, edge)] : [],
              ) || []
            const repoLabels =
              // eslint-disable-next-line no-restricted-syntax
              allLabels?.nodes?.flatMap(e => (e ? [readInlineData<LabelPickerLabel$key>(LabelFragment, e)] : [])) || []
            makeCopilotRequest({issueId, title, body, type, labels: repoLabels, types: repoTypes})
          } else {
            setCopilotRequestSuccess('error')
          }
        },
        error: () => {
          setCopilotRequestSuccess('error')
        },
      })
    },
    [makeCopilotRequest],
  )

  return {
    fetchSuggestions,
    copilotRequestSuccess,
    copilotLabels,
    copilotType,
  }
}

import {useRef, useState, useCallback} from 'react'
import {CopilotAuthTokenProvider} from '@github-ui/copilot-auth-token'
import {useSafeAsyncCallback} from '@github-ui/use-safe-async-callback'
import type {Repository} from '@github-ui/item-picker/RepositoryPicker'

export type LineRange = {
  start: number
  end: number
}

export type CopilotSnippetData = {
  type: 'snippet'
  ref: string
  repoID: number
  repoName: string
  repoOwner: string
  url: string
  path: string
  commitOID: string
  languageName: string
  languageID: number
  range: LineRange
  contents?: string
  text?: string
}

export type CopilotReferenceMetadata = {
  display_name: string
  display_icon: string
  display_url: string
}

export type CopilotReference = {
  type: 'github.snippet' | 'github.text'
  data: CopilotSnippetData
  id: string
  is_implicit: boolean
  metadata: CopilotReferenceMetadata
}

const SEARCH_PROMPT = `Find all the relevant files in the codebase that are related to the following issue title and markdown content.

<issue_title>
{{IssueTitle}}
</issue_title>
<markdown_content>
{{IssueBody}}
</markdown_content>
`

export const useSearch = (issueTitle: string, issueBody: string, copilotApiUrl: string, depth: 0 | 1 | 2 | 3) => {
  const authTokenProvider = useRef(new CopilotAuthTokenProvider([]))
  const abortControllerRef = useRef<AbortController | null>(null)
  const [isSearching, setIsSearching] = useState(false)
  const [searchError, setSearchError] = useState<string>('')
  const [suggestedSnippets, setSuggestedSnippets] = useState<CopilotReference[]>([])

  const cancelSearch = useCallback(() => {
    if (abortControllerRef.current) {
      abortControllerRef.current.abort()
      abortControllerRef.current = null
      setIsSearching(false)
    }
  }, [])

  const search = useSafeAsyncCallback(
    async ({repository, callback}: {repository: Repository; callback?: (snippets: CopilotReference[]) => void}) => {
      try {
        cancelSearch()

        const token = await authTokenProvider.current.getAuthToken()
        const requestPath = `${copilotApiUrl}/agents/github-search-agent`
        const headers: {[key: string]: string} = {
          Authorization: token.authorizationHeaderValue,
          'copilot-integration-id': 'copilot-embedded-experience',
          'Content-Type': 'application/json',
        }

        const task = SEARCH_PROMPT.replace('{{IssueTitle}}', issueTitle).replace('{{IssueBody}}', issueBody)

        const requestBody = {
          messages: [
            {
              role: 'user',
              copilot_references: [
                {
                  type: 'github.searchInputs',
                  data: {
                    type: 'search-inputs',
                    id: 0,
                    depth,
                    task,
                    owner: repository.owner.login,
                    repositoryName: repository.name,
                    includeTextRefs: true,
                  },
                },
              ],
              name: 'question',
            },
          ],
        }

        setIsSearching(true)
        setSearchError('')

        let text = ''

        // Create a new AbortController for this request
        abortControllerRef.current = new AbortController()
        const signal = abortControllerRef.current.signal

        const response = await fetch(requestPath, {
          method: 'POST',
          mode: 'cors',
          cache: 'no-cache',
          headers,
          body: JSON.stringify(requestBody),
          signal,
        })

        if (!response.ok || response.body === null) {
          let errorText = 'An unknown error has occurred'
          try {
            errorText = await response.text()
          } catch {
            // Use default error message
          }
          setSearchError(errorText)
          setIsSearching(false)
          return
        }
        const reader = response.body.getReader()

        if (!reader) {
          throw new Error('Failed to get reader from response body')
        }

        return new ReadableStream({
          start(controller) {
            return pump()
            async function pump(): Promise<void> {
              const {done, value} = await reader.read()
              if (done) {
                controller.close()
                const snippets = parseSearchData(text)
                setIsSearching(false)
                if (callback) {
                  callback(snippets)
                }
                return
              }
              if (value) {
                text += new TextDecoder().decode(value)
                controller.enqueue(value)
              }
              return pump()
            }
          },
        })
      } catch (err) {
        setIsSearching(false)
        setSearchError(err instanceof Error ? err.message : 'An unknown error occurred')
      }
    },
  )

  const parseSearchData = (data: string): CopilotReference[] => {
    // Initialize an empty array to collect snippets
    const collectedSnippets: CopilotReference[] = []

    // Clear existing snippets
    setSuggestedSnippets([])

    // Split by newlines in case we get multiple data chunks
    const lines = data.split('\n')

    for (const line of lines) {
      // Skip empty lines
      if (!line.trim()) continue

      // Check if line starts with "data: "
      if (!line.startsWith('data: ')) continue

      try {
        // Extract the JSON part after "data: "
        const jsonStr = line.substring(5)
        const parsed = JSON.parse(jsonStr)

        // Check if the response contains copilot_references
        if (parsed.copilot_references && Array.isArray(parsed.copilot_references)) {
          // Collect the snippets
          collectedSnippets.push(...parsed.copilot_references)
          // Update the state by merging with existing snippets
          setSuggestedSnippets(prevSnippets => [...prevSnippets, ...parsed.copilot_references])
        }
      } catch {
        // Skip any lines that can't be parsed as JSON
        continue
      }
    }

    return collectedSnippets
  }

  return {
    search,
    cancelSearch,
    isSearching,
    suggestedSnippets,
    searchError,
  }
}

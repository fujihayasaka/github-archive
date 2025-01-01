import {useRef, useState, useEffect} from 'react'
import {CopilotAuthTokenProvider} from '@github-ui/copilot-auth-token'
import {useSafeAsyncCallback} from '@github-ui/use-safe-async-callback'

type LineRange = {
  start: number
  end: number
}

type CopilotSnippetData = {
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

type CopilotReferenceMetadata = {
  display_name: string
  display_icon: string
  display_url: string
}

type CopilotReference = {
  type: 'github.snippet' | 'github.text'
  data: CopilotSnippetData
  id: string
  is_implicit: boolean
  metadata: CopilotReferenceMetadata
}

const DEFAULT_OWNER = 'github'
const DEFAULT_REPOSITORY_NAME = 'github'

const snippetTemplate = `
<snippet>
  <link>{{Path}}</link>
  <url>{{Url}}</url>
  <code>
{{CodeSnippet}}
  </code>
</snippet>
`

// eslint-disable-next-line github/unescaped-html-literal
const insightTemplate = `<insight>{{Insight}}</insight>`

const formattedCodeSnippets = (snippets: CopilotReference[]) => {
  return snippets
    .filter(snippet => snippet.type === 'github.snippet')
    .map(snippet =>
      snippetTemplate
        .replace('{{Path}}', snippet.data.path)
        .replace('{{Url}}', snippet.data.url)
        .replace('{{CodeSnippet}}', snippet.data.contents || ''),
    )
    .join('\n')
}

const formattedInsights = (snippets: CopilotReference[]) => {
  return snippets
    .filter(snippet => snippet.type === 'github.text')
    .map(snippet => insightTemplate.replace('{{Insight}}', snippet.data.text || ''))
    .join('\n')
}

export const usePlanBrainstorm = (
  issueTitle: string,
  issueBody: string,
  copilotApiUrl: string,
  nameWithOwner?: string,
) => {
  const authTokenProvider = useRef(new CopilotAuthTokenProvider([]))
  const [isSearching, setIsSearching] = useState(false)
  const [isRefining, setIsRefining] = useState(false)
  const [searchError, setSearchError] = useState<string>('')
  const [refinementError, setRefinementError] = useState<string>('')
  const [suggestedSnippets, setSuggestedSnippets] = useState<CopilotReference[]>([])
  const [refinementData, setRefinementData] = useState<string>('')
  const [models, setModels] = useState<string[]>([])
  const [currentRepositoryName, currentOwner] = nameWithOwner?.split('/') || []
  const [owner, setOwner] = useState<string>(currentRepositoryName || DEFAULT_OWNER)
  const [repositoryName, setRepositoryName] = useState<string>(currentOwner || DEFAULT_REPOSITORY_NAME)

  useEffect(() => {
    const fetchModels = async () => {
      try {
        const token = await authTokenProvider.current.getAuthToken()
        const modelsUrl = `${copilotApiUrl}/models`
        const headers: {[key: string]: string} = {
          Authorization: token.authorizationHeaderValue,
          'copilot-integration-id': 'copilot-embedded-experience',
        }

        const response = await fetch(modelsUrl, {
          method: 'GET',
          mode: 'cors',
          cache: 'no-cache',
          headers,
        })

        if (response.ok) {
          const data = await response.json()
          setModels(
            data.data
              .filter((model: {model_picker_enabled: boolean}) => model.model_picker_enabled)
              .map((model: {id: string}) => model.id),
          )
        } else {
          setRefinementError('Fetching models failed. Default model will be used.')
        }
      } catch {
        setRefinementError('Fetching models failed. Default model will be used.')
      }
    }

    fetchModels()
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const search = useSafeAsyncCallback(
    async ({prompt, depth, callback}: {prompt: string | undefined; depth: number; callback?: () => void}) => {
      try {
        const token = await authTokenProvider.current.getAuthToken()
        const requestPath = `${copilotApiUrl}/agents/github-search-agent`
        const headers: {[key: string]: string} = {
          Authorization: token.authorizationHeaderValue,
          'copilot-integration-id': 'copilot-embedded-experience',
          'Content-Type': 'application/json',
        }

        const task = prompt?.replace('{{IssueTitle}}', issueTitle).replace('{{IssueBody}}', issueBody)

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
                    owner,
                    repositoryName,
                    includeTextRefs: true,
                  },
                },
              ],
              name: 'question',
            },
          ],
        }

        setIsSearching(true)
        setSuggestedSnippets([])
        setSearchError('')

        let text = ''

        const response = await fetch(requestPath, {
          method: 'POST',
          mode: 'cors',
          cache: 'no-cache',
          headers,
          body: JSON.stringify(requestBody),
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
                setIsSearching(false)
                parseSearchData(text)
                if (callback) {
                  callback()
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

  const parseSearchData = (data: string) => {
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
          // Update the state by merging with existing snippets
          setSuggestedSnippets(prevSnippets => [...prevSnippets, ...parsed.copilot_references])
        }
      } catch {
        // Skip any lines that can't be parsed as JSON
        continue
      }
    }
  }

  const refine = useSafeAsyncCallback(
    async ({
      systemPrompt,
      userPrompt,
      model,
      callback,
      snippets = suggestedSnippets,
    }: {
      systemPrompt?: string
      userPrompt?: string
      model?: string
      callback?: () => void
      snippets?: CopilotReference[]
    }) => {
      try {
        const token = await authTokenProvider.current.getAuthToken()
        const copilotChatUrl = `${copilotApiUrl}/chat/completions`
        const headers: {[key: string]: string} = {
          Authorization: token.authorizationHeaderValue,
          'copilot-integration-id': 'copilot-embedded-experience',
          'Content-Type': 'application/json',
        }

        setIsRefining(true)

        // 	return fmt.Sprintf("%s\n```\n%s\n```", snippet.File.Path, snippet.Contents)
        const userMessage = userPrompt
          ?.replace('{{IssueTitle}}', issueTitle)
          .replace('{{IssueBody}}', issueBody)
          .replace('{{CodeSnippets}}', formattedCodeSnippets(snippets))
          .replace('{{Insights}}', formattedInsights(snippets))

        const response = await fetch(copilotChatUrl, {
          headers,
          method: 'POST',
          body: JSON.stringify({
            messages: [
              {role: 'system', content: systemPrompt},
              {role: 'user', content: userMessage},
            ],
            ...(model ? {model} : {}),
          }),
        })
        const data = (await response.json()).choices[0].message.content
        setRefinementData(data)
        if (callback) {
          callback()
        }
      } catch (err) {
        setRefinementError(err instanceof Error ? err.message : 'An unknown error occurred')
      } finally {
        setIsRefining(false)
      }
    },
  )

  return {
    isSearching,
    isRefining,
    searchError,
    refinementError,
    search,
    refine,
    suggestedSnippets,
    setSuggestedSnippets,
    refinementData,
    owner,
    setOwner,
    repositoryName,
    setRepositoryName,
    models,
  }
}

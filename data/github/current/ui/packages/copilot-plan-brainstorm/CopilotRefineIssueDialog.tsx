import type {
  RepositoryPickerRepository$data as Repository,
  RepositoryPickerRepository$key,
} from '@github-ui/item-picker/RepositoryPickerRepository.graphql'
import {useState, useCallback, useId, useEffect, Suspense} from 'react'
import {graphql, readInlineData, usePreloadedQuery, useQueryLoader, type PreloadedQuery} from 'react-relay'
import {Dialog, Button, Textarea} from '@primer/react'
import {CopilotIcon, TelescopeIcon} from '@primer/octicons-react'
import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'
import {RepositoryFragment, RepositoryPicker, TopRepositories} from '@github-ui/item-picker/RepositoryPicker'
import styles from './CopilotRefineIssueDialog.module.css'
import type {RepositoryPickerTopRepositoriesQuery} from '@github-ui/item-picker/RepositoryPickerTopRepositoriesQuery.graphql'
import {useSearch} from './use-search'
import {usePlanBrainstorm} from './use-plan-brainstorm'
import type {CopilotReference} from './use-search'
import type {CopilotRefineIssueDialogQuery} from './__generated__/CopilotRefineIssueDialogQuery.graphql'
import {useSafeAsyncCallback} from '@github-ui/use-safe-async-callback'

export interface CopilotRefineIssueDialogProps {
  title?: string
  markdown: string
  copilotApiUrl: string
  owner?: string
  repoName?: string
  onClose: () => void
}

const DEFAULT_TITLE = 'Issue title is not set'

const extractFilenameFromPath = (path: string) => {
  const parts = path.split('/')
  return parts[parts.length - 1]
}

export const CopilotRefineIssueDialogGraphQLQuery = graphql`
  query CopilotRefineIssueDialogQuery($owner: String!, $name: String!) {
    repository(owner: $owner, name: $name) {
      ...RepositoryPickerRepository
    }
  }
`

export function CopilotRefineIssueDialog(props: CopilotRefineIssueDialogProps) {
  const [topReposQueryRef, loadTopRepos, disposeTopRepos] =
    useQueryLoader<RepositoryPickerTopRepositoriesQuery>(TopRepositories)

  const [currentRepoQueryRef, loadCurrentRepo, disposeCurrentRepo] = useQueryLoader<CopilotRefineIssueDialogQuery>(
    CopilotRefineIssueDialogGraphQLQuery,
  )

  useEffect(() => {
    loadTopRepos({topRepositoriesFirst: 5, hasIssuesEnabled: true, owner: null}, {fetchPolicy: 'store-or-network'})
    return () => {
      disposeTopRepos()
    }
  }, [disposeTopRepos, loadTopRepos])

  useEffect(() => {
    if (props.owner && props.repoName) {
      loadCurrentRepo({owner: props.owner, name: props.repoName}, {fetchPolicy: 'store-or-network'})
    }

    return () => disposeCurrentRepo()
  }, [disposeCurrentRepo, loadCurrentRepo, props.owner, props.repoName])

  if (!topReposQueryRef || !currentRepoQueryRef) {
    return null // Return nothing while loading instead of showing a partial dialog
  }

  return (
    <Suspense>
      <CopilotRefineIssueDialogInternal
        {...props}
        topReposQueryRef={topReposQueryRef}
        currentRepoQueryRef={currentRepoQueryRef}
      />
    </Suspense>
  )
}

interface CopilotRefineIssueDialogInternalProps extends CopilotRefineIssueDialogProps {
  topReposQueryRef: PreloadedQuery<RepositoryPickerTopRepositoriesQuery>
  currentRepoQueryRef: PreloadedQuery<CopilotRefineIssueDialogQuery>
}

function CopilotRefineIssueDialogInternal({
  title = DEFAULT_TITLE,
  markdown,
  copilotApiUrl,
  onClose,
  topReposQueryRef,
  currentRepoQueryRef,
}: CopilotRefineIssueDialogInternalProps) {
  const {copilot_find_relevant_files_debug} = useFeatureFlags()
  const currentRepoData = usePreloadedQuery<CopilotRefineIssueDialogQuery>(
    CopilotRefineIssueDialogGraphQLQuery,
    currentRepoQueryRef,
  )

  const repository =
    currentRepoData && currentRepoData.repository !== undefined
      ? // eslint-disable-next-line no-restricted-syntax
        readInlineData<RepositoryPickerRepository$key>(RepositoryFragment, currentRepoData.repository) || undefined
      : null

  const [isUsingDeepSearch, setIsUsingDeepSearch] = useState<boolean>(false)
  const [selectedRepository, setSelectedRepository] = useState<Repository | undefined>(repository ?? undefined)
  const {isSearching, searchError, search, cancelSearch} = useSearch(
    title,
    markdown,
    copilotApiUrl,
    isUsingDeepSearch ? 3 : 0,
  )
  const [snippetsMarkdown, setSnippetsMarkdown] = useState<string>('')
  const [useEnhancedResults, setUseEnhancedResults] = useState<boolean>(true)
  const [isProcessingSnippets, setIsProcessingSnippets] = useState<boolean>(false)
  const [isLoadingSnippets, setIsLoadingSnippets] = useState<boolean>(false)
  const [selectedConfidence, setSelectedConfidence] = useState<number>(3) // Using values 1-5, default to middle value

  // Default system prompt for the LLM to analyze and rank snippets
  const defaultSystemPrompt = `You are an AI assistant that analyzes code snippets to determine their relevance to a given issue.

Follow these steps in order:

STEP 1: For each code snippet, assign a relevance score from 1 to 5 (1 = not relevant, 5 = highly relevant) based on how relevant the snippet is to the issue.

STEP 2: Sort all snippets by relevance score from highest to lowest.

STEP 3: For each snippet:
  - Write a one-sentence description of what the file does
  - Add a one-sentence explanation of why the snippet is relevant to the issue
  - STRICTLY LIMIT code snippets to EXACTLY 5 LINES MAXIMUM - count carefully!
  - Focus on the most important lines that demonstrate relevance to the issue
  - If needed, use ellipses (...) to indicate omitted code

Format your response as a JSON array with each snippet represented as an object containing:
[
  {
  "relevanceScore": 4, // Integer from 1 to 5
  "filename": "filename.js", // The file name extracted from the path
  "fileFunctionality": "Brief two-sentence description of the file's purpose.", // Keep this concise
  "relevanceDescription": "Brief two-sentence explanation of why this file is relevant.", // Keep this concise
  "url": "https://example.com/repo/blob/hash/path/to/filename.js#L1-L5", // The URL from the snippet
  "code": "// MAXIMUM 5 LINES ONLY - NO MORE\\nfunction example() {\\n  return true;\\n}\\n// Use ... if needed" // STRICT 5-line maximum
  },
  // Additional snippets here...
]

CRITICAL INSTRUCTIONS:
- Return ONLY valid JSON without any markdown formatting, explanations, or extra text
- ONLY analyze the code snippets provided in the {{CodeSnippets}} section
- DO NOT add any files or snippets that aren't explicitly provided
- DO NOT make up or invent code snippets that aren't in the input
- ONLY use the exact links provided in the snippets
- For each snippet, include ONLY the 5 most relevant lines of code maximum
- Include ALL snippets in your response, sorted by relevance score`

  const [customSystemPrompt, setCustomSystemPrompt] = useState<string>('')

  // Initialize the custom prompt with the default one if it's empty
  useEffect(() => {
    if (copilot_find_relevant_files_debug && !customSystemPrompt) {
      setCustomSystemPrompt(defaultSystemPrompt)
    }
  }, [copilot_find_relevant_files_debug, customSystemPrompt, defaultSystemPrompt])

  // Use the shared plan brainstorm hook for refinement
  const {
    isRefining,
    refinementError,
    refinementData,
    refine,
    setSuggestedSnippets: setPlanBrainstormSnippets,
  } = usePlanBrainstorm(title, markdown, copilotApiUrl)

  const isLoading = isSearching || isRefining

  // Process snippets through LLM for relevance sorting, confidence filtering, and descriptions
  const processSnippetsWithLLM = useSafeAsyncCallback(async (snippets: CopilotReference[]) => {
    setIsProcessingSnippets(true)

    // Filter to only include code snippets
    const codeSnippets = snippets.filter(snippet => snippet.type === 'github.snippet')

    if (codeSnippets.length === 0) {
      setSnippetsMarkdown('No code snippets found.')
      setIsProcessingSnippets(false)
      return
    }

    // Use the custom system prompt if debug flag is on, otherwise use the default
    const systemPrompt =
      copilot_find_relevant_files_debug && customSystemPrompt ? customSystemPrompt : defaultSystemPrompt

    // Create user prompt
    const userPrompt = `Analyze these code snippets for relevance to the following issue:

Issue Title: {{IssueTitle}}
Issue Description: {{IssueBody}}

Here are the code snippets to analyze:

{{CodeSnippets}}`

    try {
      await refine({
        systemPrompt,
        userPrompt,
        snippets: codeSnippets,
      })
    } catch {
      // Silently handle error
    } finally {
      setIsProcessingSnippets(false)
    }
  })

  // Function to format snippets that will be called after search completes
  const formatSnippets = useSafeAsyncCallback((snippets: CopilotReference[] = []) => {
    if (snippets.length === 0) {
      // Clear any previous content if there are no snippets
      setSnippetsMarkdown('')
      return
    }

    if (useEnhancedResults) {
      // Process snippets through LLM to enhance results
      processSnippetsWithLLM(snippets)
    } else {
      // Original snippet formatting without LLM processing
      const markdownOutput = snippets
        .filter(snippet => snippet.type === 'github.snippet')
        .map(
          snippet => `**${extractFilenameFromPath(snippet.data.path)}:**
${snippet.data.url}

\`\`\`${snippet.data.languageName}
${snippet.data.contents}
\`\`\`
`,
        )
        .join('\n\n')

      setSnippetsMarkdown(markdownOutput)
    }
  })

  const handleSearch = useSafeAsyncCallback(async () => {
    if (selectedRepository) {
      setIsLoadingSnippets(true)
      try {
        await search({
          repository: selectedRepository,
          callback: formatSnippets,
        })
      } finally {
        setIsLoadingSnippets(false)
      }
    }
  })

  const descriptionId = useId()

  // Update snippets markdown when refinement data is available
  useEffect(() => {
    if (
      refinementData &&
      useEnhancedResults &&
      !isProcessingSnippets && // Only update UI when processing is complete
      !isLoadingSnippets && // Ensure we're not still loading snippets
      refinementData.trim() !== ''
    ) {
      // Check for empty string or whitespace-only
      try {
        // First validate that the data is parseable as JSON before updating the UI
        const parsedData = JSON.parse(refinementData)

        // Only update the UI if we have valid JSON data
        if (Array.isArray(parsedData) && parsedData.length > 0) {
          setSnippetsMarkdown(convertJsonToMarkdown(refinementData))
        }
      } catch {
        // If JSON parsing fails, it might be an intermediate state or not JSON at all
        // In that case, don't update the UI yet - wait for valid data
      }
    }
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [refinementData])

  // Reset planBrainstormSnippets when component unmounts
  useEffect(() => {
    return () => {
      setPlanBrainstormSnippets([])
    }
  }, [setPlanBrainstormSnippets])

  const onDeepSearchClick = useCallback(() => {
    setIsUsingDeepSearch(!isUsingDeepSearch)
  }, [isUsingDeepSearch])
  const deepSearchText = isUsingDeepSearch ? 'Disable deep search' : 'Enable deep search'

  // Converts JSON snippet data from LLM to markdown format
  interface LLMJsonSnippet {
    relevanceScore: number
    filename: string
    fileFunctionality: string
    relevanceDescription: string
    url: string
    code: string
  }
  const convertJsonToMarkdown = (jsonData: string): string => {
    try {
      // Try to parse the JSON string into an array of objects
      const snippets: LLMJsonSnippet[] = JSON.parse(jsonData)

      // Filter out snippets that don't meet the confidence threshold
      const threshold = selectedConfidence
      const filteredData = snippets.filter(snippet => snippet.relevanceScore >= threshold)

      // If the result is not an array or is empty, return a message
      if (!Array.isArray(filteredData) || filteredData.length === 0) {
        return `No relevant snippets found based on the confidence threshold: ${jsonData}`
      }

      // Convert each snippet to a markdown section
      const markdownSections = filteredData.map(function snippetToMarkdown(snippet) {
        // Convert from 1-5 scale to percentage (1=20%, 2=40%, 3=60%, 4=80%, 5=100%)
        const confidencePercentage = Math.round((snippet.relevanceScore / 5) * 100)
        return `## ${snippet.filename} (${confidencePercentage}% confidence)

${snippet.fileFunctionality}

${snippet.relevanceDescription}

${snippet.url}

\`\`\`
${snippet.code}
\`\`\`
`
      })

      // Join all sections with double newlines
      return markdownSections.join('\n\n')
    } catch {
      // If JSON parsing fails, return the original data (might be markdown already)
      // This provides fallback behavior in case the LLM didn't return valid JSON
      return jsonData
    }
  }

  return (
    <Dialog
      title="Refine issue"
      onClose={onClose}
      width="xlarge"
      className={styles.dialog}
      renderBody={() => (
        <div className={styles.dialogBody}>
          <div className={styles.repositoryPicker}>
            <h2 className={styles.repositoryPickerHeader}>Code repository</h2>
            <RepositoryPicker
              aria-describedby={descriptionId}
              initialRepository={selectedRepository}
              onSelect={setSelectedRepository}
              organization={repository?.owner.login}
              topReposQueryRef={topReposQueryRef}
              focusRepositoryPicker
              enforceAtleastOneSelected
              options={{hasIssuesEnabled: true}}
            />
          </div>
          <div className={styles.files}>
            <div style={{display: 'flex', justifyContent: 'space-between', alignItems: 'center'}}>
              <h2 className={styles.filesHeader}>Relevant files</h2>
              {copilot_find_relevant_files_debug && (
                <div style={{display: 'flex', alignItems: 'center', gap: '12px'}}>
                  <label style={{display: 'flex', alignItems: 'center', gap: '8px', fontSize: '14px'}}>
                    <input
                      type="checkbox"
                      checked={useEnhancedResults}
                      onChange={e => setUseEnhancedResults(e.target.checked)}
                    />
                    Use AI to enhance results
                  </label>
                  {useEnhancedResults && (
                    <div style={{display: 'flex', alignItems: 'center', gap: '8px'}}>
                      <label style={{fontSize: '14px'}}>
                        Confidence: {Math.round((selectedConfidence / 5) * 100)}%
                      </label>
                      <input
                        type="range"
                        min="1"
                        max="5"
                        step="1"
                        value={selectedConfidence}
                        onChange={e => setSelectedConfidence(parseInt(e.target.value))}
                        style={{width: '120px'}}
                        aria-label="Confidence threshold percentage"
                      />
                    </div>
                  )}
                </div>
              )}
            </div>
            {copilot_find_relevant_files_debug && (
              <div className={styles.textareaContainer} style={{marginBottom: '16px'}}>
                <h3 style={{fontSize: '14px', marginBottom: '8px'}}>System Prompt</h3>
                <Textarea
                  aria-label="System Prompt"
                  id="system-prompt"
                  value={customSystemPrompt}
                  onChange={e => setCustomSystemPrompt(e.target.value)}
                  contrast
                  rows={10}
                  block
                  resize="vertical"
                  className="textarea"
                />
              </div>
            )}
            <div className={styles.textareaContainer}>
              <Textarea
                aria-label="Relevant files"
                id="relevant-files"
                value={snippetsMarkdown}
                onChange={e => setSnippetsMarkdown(e.target.value)}
                contrast
                rows={16}
                block
                resize="vertical"
                className="textarea"
              />
            </div>
          </div>
        </div>
      )}
      renderFooter={() => (
        <div className={styles.footer}>
          <div className={styles.footerSearch}>
            <Button onClick={handleSearch}>Search</Button>
            <Button leadingVisual={TelescopeIcon} onClick={onDeepSearchClick}>
              {deepSearchText}
            </Button>
            {isLoading && (
              <div className={styles.loading}>
                <CopilotIcon />
                <span>
                  Copilot is{' '}
                  {isRefining ? <span>analyzing relevance of files...</span> : <span>finding related files...</span>}
                </span>
              </div>
            )}
            {searchError && <div className="color-fg-danger">{searchError}</div>}
            {refinementError && <div className="color-fg-danger">{refinementError}</div>}
          </div>
          <div className={styles.footerActions}>
            <Button variant="default" onClick={cancelSearch} disabled={!isLoading}>
              Cancel
            </Button>
            <Button
              variant="primary"
              disabled={isLoading}
              onClick={() => navigator.clipboard.writeText(snippetsMarkdown)}
            >
              Copy
            </Button>
          </div>
        </div>
      )}
    />
  )
}

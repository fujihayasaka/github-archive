import {useState, useCallback} from 'react'
import type {ChangeEvent} from 'react'
import {Dialog, Button, Textarea, Link, Select, TextInput, Tooltip} from '@primer/react'
import {ChevronDownIcon, ChevronRightIcon, CommentIcon, FileCodeIcon, CopyIcon} from '@primer/octicons-react'
import {GroupedTextDiffViewer} from '@github-ui/markdown-edit-history-viewer/GroupedTextDiffViewer'
import {usePlanBrainstorm} from './use-plan-brainstorm'
import styles from './CopilotPlanBrainstormDialog.module.css'

export interface CopilotPlanBrainstormDialogProps {
  title?: string
  markdown: string
  copilotApiUrl: string
  nameWithOwner?: string
  onClose: () => void
}

const DEFAULT_TITLE = 'Issue title is not set'

export function CopilotPlanBrainstormDialog({
  title = DEFAULT_TITLE,
  markdown,
  copilotApiUrl,
  nameWithOwner,
  onClose,
}: CopilotPlanBrainstormDialogProps) {
  const [expandedSnippets, setExpandedSnippets] = useState<Record<string, boolean>>({})
  const [searchDepth, setSearchDepth] = useState(1)
  const [model, setModel] = useState<string | undefined>(undefined)
  const [hasRunSearch, setHasRunSearch] = useState(false)

  const {
    isSearching,
    searchError,
    isRefining,
    refinementError,
    refinementData,
    search,
    refine,
    suggestedSnippets,
    owner,
    setOwner,
    repositoryName,
    setRepositoryName,
    models,
  } = usePlanBrainstorm(title, markdown, copilotApiUrl, nameWithOwner)

  const toggleSnippet = useCallback((snippetId: string) => {
    setExpandedSnippets(current => ({
      ...current,
      [snippetId]: !current[snippetId],
    }))
  }, [])

  const [searchPrompt, setSearchPrompt] = useState(
    `Find all the relevant files in the codebase that are related to the following issue title and markdown content.

<issue_title>
{{IssueTitle}}
</issue_title>
<markdown_content>
{{IssueBody}}
</markdown_content>
`,
  )
  const [refinementSystemPrompt, setRefinementSystemPrompt] = useState(
    `You will assume the role of a product manager and write a refined GitHub Issue body based on the user provided content.
In the issue body, identify the main problem and requirements, and provide a clear and concise description of the issue.
Do not ask any follow-up questions, instead use your best efforts and knowledge available to hand and provide an answer.
Use the provided Issue title, Markdown content of the Issue body, relevant source code snippets and insights from our AI search tool to provide the final answer.
Please provide an improved version of the issue body that is more specific to the code snippets and the issue content.
Correlate the suggested snippets / related files to the issue body, and include filename as well as snippet of files where you have a high confidence that they are relevant to this issue. If you have a high confidence of a suggested change to those files, include it.
Format the relevant files / suggested code snippets as a markdown table, grouped by filename, then some explanation why this file is relevant to this issue, followed by the code in a details/summary pattern so users can expand at will.
In your response, only output the raw Markdown content and omit any other text or explanation.
`,
  )
  const [refinementUserPrompt, setRefinementUserPrompt] = useState(
    `Please refine the following issue for me:

<issue_title>
{{IssueTitle}}
</issue_title>

<markdown_content>
{{IssueBody}}
</markdown_content>

<code_snippets>
{{CodeSnippets}}
</code_snippets>

<insights>
{{Insights}}
</insights>
`,
  )

  const isLoading = isSearching || isRefining

  const handleSearch = useCallback(async () => {
    if (!isLoading) {
      await search({
        prompt: searchPrompt,
        depth: searchDepth,
      })
      setHasRunSearch(true)
    }
  }, [isLoading, search, searchPrompt, searchDepth])

  const handleRefinement = useCallback(async () => {
    if (!isLoading) {
      if (!hasRunSearch) {
        await handleSearch()
      }

      await refine({
        model,
        systemPrompt: refinementSystemPrompt,
        userPrompt: refinementUserPrompt,
      })
    }
  }, [isLoading, hasRunSearch, refine, model, refinementSystemPrompt, refinementUserPrompt, handleSearch])

  const pluralize = (count: number) => {
    if (count === 1) {
      return 'snippet'
    }
    if (count % 10 === 1 && count % 100 !== 11) {
      return 'snippet'
    }
    return 'snippets'
  }

  return (
    <Dialog
      title="Plan & Brainstorm with GitHub Copilot"
      onClose={onClose}
      width="xlarge"
      renderFooter={() => (
        <div className={styles.dialogFooter}>
          <div className={styles.refineControls}>
            <div>
              {models.length > 0 && (
                <div className={styles.selectContainer}>
                  <label htmlFor="model">Model:</label>
                  <Select
                    id="model"
                    aria-label="Model"
                    value={model}
                    onChange={(e: ChangeEvent<HTMLSelectElement>) => setModel(e.target.value)}
                  >
                    {models.map(m => (
                      <Select.Option key={m} value={m.toString()}>
                        {m}
                      </Select.Option>
                    ))}
                  </Select>
                </div>
              )}
            </div>
            <Button onClick={handleRefinement} loading={isRefining} disabled={isLoading} variant="primary">
              Refine Issues Body
            </Button>
          </div>
        </div>
      )}
      renderBody={() => (
        <div className={styles.dialogBody}>
          <div className={styles.dialogHeader}>
            <label htmlFor="owner">Owner:</label>
            <TextInput id="owner" value={owner} onChange={e => setOwner(e.target.value)} />
            <label htmlFor="repo">Repo:</label>
            <TextInput id="repo" value={repositoryName} onChange={e => setRepositoryName(e.target.value)} />
          </div>
          <div className={styles.stepContent}>
            <label htmlFor="search-prompt">Search prompt</label>
            <Textarea
              aria-label="Prompt"
              id="search-prompt"
              placeholder="Enter your prompt"
              value={searchPrompt}
              onChange={(e: ChangeEvent<HTMLTextAreaElement>) => setSearchPrompt(e.target.value)}
              contrast
              rows={8}
              block
              resize="vertical"
              className={styles.promptTextArea}
            />
            <div className={styles.searchControls}>
              <div className={styles.selectContainer}>
                <label htmlFor="depth">Search depth:</label>
                <Select
                  id="depth"
                  aria-label="Search depth"
                  value={searchDepth}
                  onChange={(e: ChangeEvent<HTMLSelectElement>) => {
                    setSearchDepth(Number(e.target.value))
                    setHasRunSearch(false)
                  }}
                >
                  {[0, 1, 2, 3, 4].map(depth => (
                    <Select.Option key={depth} value={depth.toString()}>
                      {depth}
                    </Select.Option>
                  ))}
                </Select>
              </div>
              <div className={styles.selectContainer}>
                {hasRunSearch && suggestedSnippets.length > 0 && (
                  <span>
                    Found {suggestedSnippets.length} {pluralize(suggestedSnippets.length)}
                  </span>
                )}
                <Button onClick={handleSearch} loading={isSearching} disabled={isLoading}>
                  Send to CAPI search
                </Button>
              </div>
            </div>
            {searchError && <div className="color-fg-danger">{searchError}</div>}
          </div>

          <div className={styles.stepContent}>
            <label htmlFor="refine-system-prompt">Refinement system prompt</label>
            <Textarea
              aria-label="System Prompt"
              id="refine-system-prompt"
              placeholder="Enter your system prompt"
              value={refinementSystemPrompt}
              onChange={(e: ChangeEvent<HTMLTextAreaElement>) => setRefinementSystemPrompt(e.target.value)}
              contrast
              rows={12}
              block
              resize="vertical"
            />
            <label htmlFor="refine-user-prompt">Refinement user prompt</label>
            <Textarea
              aria-label="User Prompt"
              id="refine-user-prompt"
              placeholder="Enter your user prompt"
              value={refinementUserPrompt}
              onChange={(e: ChangeEvent<HTMLTextAreaElement>) => setRefinementUserPrompt(e.target.value)}
              contrast
              rows={12}
              block
              resize="vertical"
            />
            {refinementError && <div className="color-fg-danger">{refinementError}</div>}
          </div>
          {suggestedSnippets.length > 0 && (
            <div className={styles.stepContent}>
              <label htmlFor="snippets">Suggested snippets</label>
              <div id="snippets">
                {suggestedSnippets.map(snippet => (
                  <div key={snippet.id} className={styles.snippet}>
                    <div className={styles.snippetHeader}>
                      <Button
                        variant="invisible"
                        className={styles.stepButton}
                        onClick={() => toggleSnippet(snippet.id)}
                      >
                        {expandedSnippets[snippet.id] ? <ChevronDownIcon /> : <ChevronRightIcon />}
                        {snippet.type === 'github.text' ? (
                          <>
                            <CommentIcon />
                            <span>text</span>
                          </>
                        ) : (
                          <>
                            <FileCodeIcon />
                            <span>{snippet.metadata.display_name}</span>
                          </>
                        )}
                      </Button>
                    </div>
                    {expandedSnippets[snippet.id] && (
                      <div className={styles.snippetContent}>
                        {snippet.data.url && <Link href={snippet.data.url}>View source</Link>}
                        {snippet.type === 'github.snippet' && <pre>{snippet.data.contents}</pre>}
                        {snippet.type === 'github.text' && <span>{snippet.data.text}</span>}
                      </div>
                    )}
                  </div>
                ))}
              </div>
            </div>
          )}
          {refinementData && (
            <div className={styles.stepContent}>
              <div className={styles.refinementHeader}>
                <label htmlFor="refinement">Issue body refinement</label>
                <Tooltip aria-label="Copy to clipboard" direction="n" text="Copy to clipboard">
                  <Button variant="invisible" onClick={() => navigator.clipboard.writeText(refinementData)}>
                    <CopyIcon />
                  </Button>
                </Tooltip>
              </div>
              <div id="refinement">
                <GroupedTextDiffViewer before={markdown} after={refinementData} />
              </div>
            </div>
          )}
        </div>
      )}
    />
  )
}

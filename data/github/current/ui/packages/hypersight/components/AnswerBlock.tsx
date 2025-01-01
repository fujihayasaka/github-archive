import {useState, useEffect} from 'react'
import {streamingGenerateAnswer} from '../utils/generate-answer'
import {
  CheckCircleIcon,
  SearchIcon,
  ChevronDownIcon,
  ChevronRightIcon,
  TasklistIcon,
  CopilotWarningIcon,
} from '@primer/octicons-react'
import type {PullRequest, HydratedIssueReference, AnswerStatus, DiffHunk} from '../utils/types'
import {Button, ProgressBar} from '@primer/react'
import {SkeletonText} from '@primer/react/experimental'
import {MarkdownRenderer} from '@github-ui/copilot-markdown'
import styles from './AnswerBlock.module.css'

type AnswerBlockProps = {
  apiUrl: string
  question: string
  pullRequest: PullRequest
  extractedIssues: HydratedIssueReference[]
  diffs: DiffHunk[]
  id?: string
  onAnswerComplete?: () => void
  isLoading?: boolean
}

export function AnswerBlock({
  apiUrl,
  question,
  pullRequest,
  extractedIssues,
  diffs,
  id,
  onAnswerComplete,
  isLoading = false,
}: AnswerBlockProps) {
  const [answer, setAnswer] = useState<string | null>(null)
  const [status, setStatus] = useState<AnswerStatus | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [isStreaming, setIsStreaming] = useState<boolean>()

  useEffect(() => {
    let isMounted = true
    const abortController = new AbortController()

    const generateAnswer = async () => {
      if (!isLoading) return // Only generate answer when isLoading is true

      try {
        // Get streaming response
        const generator = streamingGenerateAnswer(apiUrl, question, pullRequest, extractedIssues, diffs)

        if (!isMounted) return

        // Initialize with empty response only when we start receiving new content
        let isFirstChunk = true
        for await (const messageUpdate of generator) {
          if (isFirstChunk) {
            setAnswer('')
            isFirstChunk = false
          }
          if (messageUpdate.step === 'data') {
            setAnswer(currentAnswer => `${currentAnswer}${messageUpdate.message}`)
          } else {
            setStatus(messageUpdate)

            // If there's an error in the status, set the error state
            if (messageUpdate.step === 'error') {
              setError(messageUpdate.message)
            }

            if (messageUpdate.step === 'complete') {
              break
            }
          }
        }

        setIsStreaming(false)

        onAnswerComplete?.()
      } catch (err) {
        // eslint-disable-next-line no-console
        console.error('Error answering question:', err)
        if (isMounted) {
          setError('Failed to generate an answer.')
          setAnswer(null)
          onAnswerComplete?.()
          setIsStreaming(false)
        }
      }
    }

    generateAnswer()

    return () => {
      isMounted = false
      abortController.abort()
    }
  }, [question, pullRequest, extractedIssues, onAnswerComplete, isLoading, apiUrl, diffs])

  const answerId = id || `answer-${question.slice(0, 20).replace(/\W+/g, '-').toLowerCase()}`

  if (error) {
    return (
      <div id={answerId}>
        <div>
          <SearchIcon size={16} />
          <h3>{question}</h3>
        </div>
        <div>
          <div>{error}</div>
        </div>
      </div>
    )
  }

  return (
    <div id={answerId} className="markdown-body pb-3">
      <h2>{question}</h2>
      {answer ? (
        <div>
          <MarkdownRenderer markdown={answer} isStreaming={isStreaming} />
          <SearchResults status={status} />
        </div>
      ) : (
        <div>
          <AnswerSkeleton status={status} />
        </div>
      )}
    </div>
  )
}

function SearchResults({status}: {status: AnswerStatus | null}) {
  const [showSearches, setShowSearches] = useState(false)

  if (!status?.searches || status.searches.length === 0) {
    return null
  }

  return (
    <>
      <div className={styles.answers}>
        <Button
          onClick={() => setShowSearches(!showSearches)}
          leadingVisual={showSearches ? ChevronDownIcon : ChevronRightIcon}
          variant="link"
        >
          {showSearches ? <>Hide search details</> : <>Show search details</>}
        </Button>

        {showSearches && (
          <div>
            <div>
              <p>Searches performed:</p>
            </div>
            <ol>
              {status.searches.map(search => (
                <li key={search.question}>
                  <div key={search.question}>
                    <div>{search.question}</div>
                    <div>
                      <span>
                        <span>
                          Showing top <span>{search.topResults?.length ?? 0}</span>
                        </span>
                        <span> of {search.totalResults} total results.</span>
                      </span>
                    </div>
                    {search.topResults && search.topResults.length > 0 && (
                      <div>
                        <div>
                          <ul>
                            {search.topResults.map(result => (
                              <li key={result.url}>
                                <div key={result.url}>
                                  <a
                                    href={result.url}
                                    target="_blank"
                                    rel="noopener noreferrer"
                                    // className="text-zinc-900 block hover:underline p-0.5"
                                  >
                                    {result.path}
                                  </a>
                                </div>
                              </li>
                            ))}
                          </ul>
                        </div>
                      </div>
                    )}
                  </div>
                </li>
              ))}
            </ol>
          </div>
        )}
      </div>
    </>
  )
}

function AnswerSkeleton({status}: {status: AnswerStatus | null}) {
  // Default message if no status is available
  const message = status?.message || 'Searching codebase...'
  const progress = status?.progress || 0

  return (
    <div>
      <div>
        <ProgressBar progress={progress} aria-label="Generating answers" />
      </div>
      <div>
        {status?.step === 'generating-questions' && <SearchIcon size={16} />}
        {status?.step === 'searching-code' && <SearchIcon size={16} className="anim-pulse" />}
        {status?.step === 'generating-answer' && <TasklistIcon size={16} />}
        {status?.step === 'complete' && <CheckCircleIcon size={16} />}
        {status?.step === 'error' && <CopilotWarningIcon size={16} />}
        <span>{message}</span>
      </div>

      <div>
        <SkeletonText lines={3} />
      </div>
    </div>
  )
}

import {useState, useEffect} from 'react'
import {streamingGenerateAnswer} from '../utils/generate-answer'
import {ChevronDownIcon, ChevronRightIcon} from '@primer/octicons-react'
import type {PullRequest, HydratedIssueReference, AnswerStatus, DiffHunk, SearchInfo} from '../utils/types'
import {Button, ProgressBar} from '@primer/react'
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
      <div id={answerId} className={styles.answerBlockWithError}>
        <h3 className={styles.questionTitle}>{question}</h3>
        <div>{error}</div>
      </div>
    )
  }

  return (
    <div id={answerId} className={styles.answerBlock}>
      <h3 className={styles.questionTitle}>{question}</h3>
      {answer ? (
        <>
          <SearchResults status={status} />
          <div className="markdown-body">
            <MarkdownRenderer markdown={answer} isStreaming={isStreaming} />
          </div>
        </>
      ) : (
        <AnswerSkeleton status={status} />
      )}
    </div>
  )
}

function SearchItemResult({result}: {result: {path: string; url: string}}) {
  return (
    <div className={styles.searchItemResult}>
      <a href={result.url} target="_blank" rel="noopener noreferrer">
        {result.path}
      </a>
    </div>
  )
}

function SearchItem({search}: {search: SearchInfo}) {
  const summary = `Showing top ${search.topResults?.length ?? 0} of ${search.totalResults} total results.`
  return (
    <div>
      <div className={styles.searchItemQuestion}>{search.question}</div>
      <div className={styles.searchItemSummary}>{summary}</div>
      {search.topResults && search.topResults.length > 0 && (
        <div className={styles.searchItemResults}>
          {search.topResults.map(result => (
            <SearchItemResult result={result} key={result.url} />
          ))}
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
      <div className={styles.searches}>
        <Button
          onClick={() => setShowSearches(!showSearches)}
          leadingVisual={showSearches ? ChevronDownIcon : ChevronRightIcon}
          variant="invisible"
          size="small"
        >
          {showSearches ? <>Hide search details</> : <>Show search details</>}
        </Button>

        {showSearches && (
          <div className={styles.searchResultsPanel}>
            <h3 className={styles.title}>
              {status.searches.length === 1 ? (
                <>Copilot performed the following search</>
              ) : (
                <>Copilot performed {status.searches.length} searches</>
              )}
            </h3>
            {status.searches.map(search => (
              <SearchItem search={search} key={search.question} />
            ))}
          </div>
        )}
      </div>
    </>
  )
}

function AnswerSkeleton({status}: {status: AnswerStatus | null}) {
  const message = status?.message || 'Searching codebase...'
  const progress = status?.progress || 0

  return (
    <div className={styles.answerSkeleton}>
      <div>
        <h3 className={styles.title}>Copilot is working on an answer</h3>
        <div className={styles.statusMessage}>{message}</div>
      </div>
      <ProgressBar bg="done.emphasis" progress={progress} aria-label="Generating answers" />
    </div>
  )
}

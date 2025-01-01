import {announce} from '@github-ui/aria-live'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useQuery} from '@github-ui/react-query'
import {SafeHTMLBox} from '@github-ui/safe-html'
import {Button, Label} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {Tooltip} from '@primer/react/next'
import {clsx} from 'clsx'
import {useEffect, useMemo, useRef, useState} from 'react'

import {useCurrentPullRequest} from '../contexts/CurrentPullRequestProvider'
import {useFilesContext} from '../contexts/FilesContext'
import {useWorkspaceEditorAppContext} from '../contexts/WorkspaceEditorAppContext'
import {useLocalSuggestionState} from '../hooks/use-local-suggestion-state'
import suggesterName from '../utilities/suggester-name'
import {
  findSuggestion,
  getPayloadsForSuggestion,
  isSuggestionAlreadyApplied,
  problemWithSingleSuggestion,
  problemWithTaskSuggestions,
} from '../utilities/suggestion-helpers'
import type {
  BlobPayload,
  DisplayTaskData,
  FocusedTaskData,
  WorkspaceEditorRoutePayload,
} from '../utilities/workspace-editor-types'
import {ThreadComment} from './generate-fix-panel/PullRequestThread'
import {RightSidePanelContent} from './RightSidePanelComponents'
import {SuggesterAvatar} from './SuggesterAvatar'
import styles from './Suggestion.module.css'
import {SuggestionFooter} from './suggestions/SuggestionFooter'

// This is only used with the server-emitted buttons on our diffs.
// It's also rather coupled to the Primer tooltip specifics in play here.
// UI rendering that we control should obviously be done the normal way.
function disableButtonWithTooltip(button: HTMLElement, tooltipText: string) {
  button.setAttribute('aria-disabled', 'true')
  button.classList.add('Button--inactive')
  const tooltip = button.nextElementSibling
  if (tooltip instanceof HTMLElement && tooltip.tagName === 'TOOL-TIP') {
    tooltip.classList.remove('v-hidden')
    tooltip.textContent = tooltipText
  }
}

export const Suggestion = ({
  currentTask,
  onSuggestionApplied,
  suggestionsForPagination,
}: {
  currentTask: FocusedTaskData
  onSuggestionApplied?: (task: FocusedTaskData) => void
  suggestionsForPagination: DisplayTaskData[]
}) => {
  const [suggestionError, setSuggestionError] = useState(false)
  const payload = useRoutePayload<WorkspaceEditorRoutePayload>()
  const {applyAllTaskSuggestionsToContent, applySuggestionsToContent, getCurrentFileContent, getFileStatuses} =
    useFilesContext()
  const {getAppliedSuggestions, isSingleSuggestionApplied} = useLocalSuggestionState()
  const {blobService} = useWorkspaceEditorAppContext()
  const appliedSuggestions = getAppliedSuggestions()
  const {previousComments = [], followingComments = []} = currentTask
  const [expandPreviousComments, setExpandPreviousComments] = useState(false)
  const [expandFollowingComments, setExpandFollowingComments] = useState(false)

  const hasPreviousComments = !!previousComments.length
  const hasFollowingComments = !!followingComments.length

  const showPreviousComments = useMemo(() => {
    return hasPreviousComments && expandPreviousComments
  }, [expandPreviousComments, hasPreviousComments])

  const showFollowingComments = useMemo(() => {
    return hasFollowingComments && expandFollowingComments
  }, [expandFollowingComments, hasFollowingComments])

  const contextCommentsExpanded = showPreviousComments || showFollowingComments

  const {pullRequest} = useCurrentPullRequest()

  const {
    isError,
    isLoading,
    data: originals,
  } = useQuery({
    queryKey: ['get-original-payloads', pullRequest, currentTask, blobService, payload],
    queryFn: async (): Promise<BlobPayload[]> => {
      return await getPayloadsForSuggestion(blobService, pullRequest, currentTask, payload)
    },
    refetchOnMount: false,
    refetchOnReconnect: false,
    refetchOnWindowFocus: false,
  })

  // We calculate current outside of fetching original because it may change
  // more often than our `useQuery` result will and we want it up to date.
  let originalsAndCurrentContents: Array<[BlobPayload, string | undefined]> = []
  if (originals) {
    originalsAndCurrentContents = originals.map(original => [
      original,
      getCurrentFileContent(original.path, original.blobContents)['content'],
    ])
  }

  const problem = problemWithTaskSuggestions(
    appliedSuggestions,
    getFileStatuses(),
    currentTask,
    originalsAndCurrentContents,
  )
  const canApply = !problem && !isError && !isLoading
  const applyTooltip = problem || ''

  const isSuggestionApplied = isSuggestionAlreadyApplied(appliedSuggestions, currentTask.sourceId)

  useEffect(() => {
    setSuggestionError(!canApply && !isSuggestionApplied)
  }, [canApply, isSuggestionApplied])

  // We dynamically wire up to the Apply buttons in the server-emitted diffs
  const htmlRef = useRef<HTMLDivElement>(null)
  useEffect(() => {
    if (htmlRef.current) {
      const clickHandler = async (e: MouseEvent) => {
        if (e.currentTarget instanceof HTMLElement) {
          if (e.currentTarget.getAttribute('aria-disabled')) return

          e.preventDefault()
          const path = e.currentTarget.getAttribute('data-path')
          const index = e.currentTarget.getAttribute('data-index')
          const suggestion = findSuggestion(currentTask, path, index)
          const original = originals?.find(check => check.path === suggestion?.filePath)

          if (suggestion && original) {
            try {
              applySuggestionsToContent([suggestion], [original], currentTask)
              announce('Suggestion applied.')
            } catch (err: Error | unknown) {
              if (err instanceof Error) {
                alert(err.message)
              } else {
                throw err
              }
            }
          }
        }
      }

      const buttons = htmlRef.current.querySelectorAll('button[data-path]')
      for (const button of buttons) {
        if (button instanceof HTMLElement) {
          const path = button.getAttribute('data-path')
          const index = button.getAttribute('data-index')
          const suggestion = findSuggestion(currentTask, path, index)
          if (suggestion) {
            button.addEventListener('click', clickHandler)
            const singleProblem = problemWithSingleSuggestion(
              currentTask,
              suggestion,
              isSingleSuggestionApplied,
              originalsAndCurrentContents,
            )

            if (singleProblem) {
              disableButtonWithTooltip(button, singleProblem)
            }
          } else {
            // If for some reason we can't find the related suggestion, hide it
            button.hidden = true
          }
        }
      }

      return () => {
        for (const button of buttons) {
          if (button instanceof HTMLElement) {
            button.removeEventListener('click', clickHandler)
          }
        }
      }
    }
  })

  return (
    <>
      {suggestionError && (
        <div style={{margin: '8px'}}>
          <Banner
            variant="critical"
            onDismiss={() => setSuggestionError(false)}
            description={'Cannot apply suggestion to current content.'}
          >
            <Banner.Title />
          </Banner>
        </div>
      )}
      <RightSidePanelContent error={suggestionError}>
        <div className="d-flex flex-column gap-4">
          {hasPreviousComments && !showPreviousComments && (
            <Button
              size="small"
              alignContent="start"
              variant="invisible"
              className="flex-self-start"
              onClick={() => setExpandPreviousComments(true)}
            >
              {`Show ${previousComments.length} previous ${previousComments.length === 1 ? 'comment' : 'comments'}`}
            </Button>
          )}
          {showPreviousComments &&
            previousComments.map(c => (
              <ThreadComment comment={{author: c.author, body: c.html, id: c.id}} key={c.id} />
            ))}
          <div className={clsx(contextCommentsExpanded && 'border color-border-accent-emphasis rounded-2 p-3')}>
            <div className="mb-2 d-inline-flex flex-row flex-justify-between width-full">
              <div>
                <SuggesterAvatar className="pr-2" suggester={currentTask.author} />
                <span className="f4 text-semibold">{suggesterName(currentTask.author)}</span>
              </div>
              <div>{currentTask.outdated && <Label variant="attention">Outdated</Label>}</div>
            </div>
            <div>
              <SafeHTMLBox
                className={clsx('markdown-body mt-1 f5', styles.suggestionMarkdown, styles.suggestionHtmlBox)}
                html={currentTask.html}
                ref={htmlRef}
              />
            </div>
          </div>
          {hasFollowingComments && !showFollowingComments && (
            <Button
              size="small"
              alignContent="start"
              variant="invisible"
              onClick={() => setExpandFollowingComments(true)}
              className={styles.Button}
            >
              {`Show ${followingComments.length} following ${followingComments.length === 1 ? 'comment' : 'comments'}`}
            </Button>
          )}
          {showFollowingComments &&
            followingComments.map(c => (
              <ThreadComment comment={{author: c.author, body: c.html, id: c.id}} key={c.id} />
            ))}
        </div>
      </RightSidePanelContent>
      <SuggestionFooter
        applyButton={
          <ApplyButton
            currentTask={currentTask}
            applyTooltip={applyTooltip}
            canApply={canApply}
            originals={originals}
            applyAllTaskSuggestionsToContent={applyAllTaskSuggestionsToContent}
            onSuggestionApplied={onSuggestionApplied}
          />
        }
        showSuggestionApplied={isSuggestionApplied}
        suggestionsForPagination={suggestionsForPagination}
      />
    </>
  )
}

const ApplyButton = ({
  currentTask,
  applyTooltip,
  canApply,
  originals,
  applyAllTaskSuggestionsToContent,
  onSuggestionApplied,
}: {
  currentTask: FocusedTaskData
  applyTooltip: string
  canApply: boolean
  originals: BlobPayload[] | undefined
  applyAllTaskSuggestionsToContent: (
    task: FocusedTaskData,
    originals: BlobPayload[],
  ) => {
    [filePath: string]: string | undefined
  }
  onSuggestionApplied?: (task: FocusedTaskData) => void
}) => {
  return (
    <Tooltip hidden={canApply} text={applyTooltip} direction="nw">
      <Button
        aria-disabled={!canApply}
        inactive={!canApply}
        variant="primary"
        onClick={async () => {
          if (!canApply) return
          if (!originals) return

          try {
            applyAllTaskSuggestionsToContent(currentTask, originals)
            onSuggestionApplied?.(currentTask)
          } catch (err: Error | unknown) {
            if (err instanceof Error) {
              alert(err.message)
            } else {
              throw err
            }
          }
        }}
      >
        Apply
      </Button>
    </Tooltip>
  )
}

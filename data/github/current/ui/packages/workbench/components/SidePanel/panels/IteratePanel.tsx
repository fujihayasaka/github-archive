import {announce} from '@github-ui/aria-live'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {isMobile} from '@github-ui/get-os'
import {useLayoutEffect} from '@github-ui/use-layout-effect'
import {
  BugIcon,
  ChevronRightIcon,
  DotFillIcon,
  ImageIcon,
  PaperAirplaneIcon,
  PaperclipIcon,
  SquareFillIcon,
  XIcon,
} from '@primer/octicons-react'
import {IconButton, Label, Timeline, Token} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {clsx} from 'clsx'
import {useCallback, useEffect, useMemo, useRef, useState} from 'react'

import {useContentFilter} from '../../../contexts/ContentFilterContext'
import {useEditorContext} from '../../../contexts/EditorContext'
import {useErrors} from '../../../contexts/ErrorsContext'
import {useIterationHistory} from '../../../contexts/IterationHistoryContext'
import {ReadOnlyProvider, useReadOnly} from '../../../contexts/ReadOnlyContext'
import {useUserPromptContext} from '../../../contexts/UserPromptContext'
import {useWorkbenchContext} from '../../../contexts/WorkbenchContext'
import {useWorkbenchStore} from '../../../contexts/WorkbenchStoreContext'
import {Region, RegionState, useRegionState} from '../../../hooks/use-region-state'
import {useStableCallback} from '../../../hooks/use-stable-callback'
import {useWorkbench, type UseWorkbenchReturn} from '../../../hooks/use-workbench'
import type {Iteration} from '../../../types/workbench-types'
import {attachedErrorsPromptPrefix, fixAllPrompt, generateErrorsPrompt, type SparkError} from '../../../utilities/error'
import AgentActivity from '../../AgentActivity'
import Suggestions from '../../Suggestions'
import {Overscroll} from '../Overscroll'
import styles from './IteratePanel.module.css'

type AttachableError = SparkError & {attached: boolean; dismissed?: boolean}
const getAttachments = (errors: AttachableError[]) => ({errors: errors.map(e => ({message: e.messageRaw}))})

interface IteratePanelProps {
  workbenchData: UseWorkbenchReturn
}
const IteratePanel = ({workbenchData}: IteratePanelProps) => {
  const {cancelPrompt, isFetching, submitPrompt, suggestions, setIsMobileSidebarOpen} = workbenchData
  const {
    promptText,
    setPromptText,
    promptError,
    setPromptError,
    promptImage,
    attachImage,
    clearImageAttachment,
    imageUploadError,
    setImageUploadError,
  } = useUserPromptContext()
  const {previousRefinements, currentRefinementId, setIsNavigatingHistory} = useIterationHistory()
  const {updatePartialWorkbench, updateRefinementAndFiles} = useWorkbench()
  const {filterExplanationContent} = useContentFilter()
  const {forceEditorRefresh} = useEditorContext()

  const {iterateErrors, deployBuildErrors, setDeployBuildErrors} = useErrors()
  const [errors, setErrors] = useState<AttachableError[]>([])
  const attachedErrors = errors.filter(er => er.attached)

  const promptInputRef = useRef<HTMLTextAreaElement>(null)
  const imageUploadErrorRef = useRef<HTMLDivElement>(null)
  const imagesInputRef = useRef<HTMLInputElement>(null)
  const attachImageButtonRef = useRef<HTMLButtonElement>(null)
  const scrollRef = useRef<HTMLDivElement>(null)

  const readOnly = useRegionState(Region.ITERATE) === RegionState.READ_ONLY
  const workbenchStore = useWorkbenchStore()
  const step = previousRefinements.length ? 'refine' : 'generate'

  useLayoutEffect(() => {
    const el = scrollRef.current
    if (el) el.scrollTop = el.scrollHeight
  }, [])

  useLayoutEffect(() => {
    const el = promptInputRef.current
    if (el) {
      el.style.height = 'auto'
      el.style.height = `${el.scrollHeight}px`
    }
  }, [promptText])

  const activeRefinement = useMemo(
    () => previousRefinements.find(r => r.id === currentRefinementId),
    [previousRefinements, currentRefinementId],
  )

  useEffect(() => {
    setErrors(prevErrors => {
      const existing = new Map(prevErrors.map(e => [e.messageRaw, {attached: e.attached, dismissed: e.dismissed}]))
      return iterateErrors.map(e => ({
        source: e.source,
        messageRaw: e.messageRaw,
        messagePretty: e.messagePretty,
        path: e.path,
        line: e.line,
        column: e.column,
        location: e.location,
        attached: existing.get(e.messageRaw)?.attached ?? false,
        dismissed: existing.get(e.messageRaw)?.dismissed ?? false,
      }))
    })
  }, [iterateErrors])

  useEffect(() => {
    // Focus the image upload error banner when it appears
    if (imageUploadError) {
      imageUploadErrorRef.current?.focus()
    }
  }, [imageUploadError])

  const attachAll = useCallback((attached: boolean) => {
    setErrors(prev => {
      const updated = prev.map(e => ({...e, attached}))
      return updated
    })
  }, [])

  const handleSubmit = useStableCallback(async (prompt: string, method: string) => {
    const currentDeployBuildErrors = deployBuildErrors

    workbenchStore.reloadQuota()

    setPromptText('')
    setDeployBuildErrors([])
    setIsMobileSidebarOpen(false)
    setPromptError(null)

    let result: {success: boolean; error?: Error | null} | undefined = undefined
    const shouldReplace = Boolean(filterExplanationContent)

    if (copilotFeatureFlags.workbenchVMAgentAttachments) {
      const attachments = getAttachments(attachedErrors)
      result = await submitPrompt(prompt, step, method, shouldReplace, attachments)
      if (attachments.errors.length !== 0) {
        attachAll(false)
      }
    } else {
      let newPrompt = prompt
      if (attachedErrors.length !== 0) {
        newPrompt = generateErrorsPrompt(
          prompt,
          attachedErrors.map(er => er.messageRaw),
        )
        attachAll(false)
      }

      result = await submitPrompt(newPrompt, step, method, shouldReplace)
    }

    // reset values back on error
    if (!result?.success) {
      setPromptText(prompt)
      setDeployBuildErrors(currentDeployBuildErrors)
      setPromptError(result?.error?.message ?? 'Failed to process prompt.')
    }
  })

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      if (e.key !== 'Enter' || e.shiftKey || isMobile()) return

      e.preventDefault()
      handleSubmit(promptText, 'handleKeyDown')
    },
    [promptText, handleSubmit],
  )

  const fixAll = () => {
    if (errors.length === 0) return
    if (copilotFeatureFlags.workbenchVMAgentAttachments) {
      const attachments = getAttachments(errors)
      submitPrompt(fixAllPrompt, step, 'attachments', false, attachments)
    } else {
      const promptWithErrors = generateErrorsPrompt(
        fixAllPrompt,
        errors.map(e => e.messageRaw),
      )
      submitPrompt(promptWithErrors, step)
    }

    attachAll(false)
    setDeployBuildErrors([])
  }

  const handleImageRemove = () => {
    clearImageAttachment()
    announce('Image removed')
    promptInputRef.current?.focus()
  }

  return (
    <ReadOnlyProvider readOnly={readOnly}>
      <div className={styles.container}>
        <Overscroll scrollingRef={scrollRef} />
        <div ref={scrollRef} className={styles.contentArea}>
          <ActivityLog
            activeRefinement={activeRefinement!}
            previousRefinements={previousRefinements.map(pr => ({
              ...pr,
              prompt: pr.prompt?.includes(attachedErrorsPromptPrefix)
                ? pr.prompt.split(attachedErrorsPromptPrefix)[0]
                : pr.prompt,
            }))}
            onSelectRefinement={async (refinementId: number) => {
              setIsNavigatingHistory(true)
              await Promise.all([
                forceEditorRefresh(),
                updateRefinementAndFiles(refinementId),
                updatePartialWorkbench({currentRefinementId: refinementId}),
              ])
              setIsNavigatingHistory(false)
            }}
            filterExplanationContent={filterExplanationContent}
          />
        </div>
        {imageUploadError && (
          <Banner
            className={styles.alertBanner}
            ref={imageUploadErrorRef}
            variant="critical"
            title="Error attaching image"
            description={imageUploadError}
            hideTitle
            onDismiss={() => {
              attachImageButtonRef.current?.focus()
              setImageUploadError(undefined)
            }}
          />
        )}
        {promptError && (
          <Banner
            className={styles.alertBanner}
            variant="critical"
            title="Failed"
            description={promptError}
            hideTitle
            onDismiss={() => {
              promptInputRef.current?.focus()
              setPromptError(null)
            }}
          />
        )}
        {(suggestions.length > 0 || errors.length > 0) && (
          <Suggestions
            suggestions={suggestions}
            errors={errors}
            onSelectSuggestion={suggestion => handleSubmit(suggestion, 'suggestion')}
            attachAll={attachAll}
            fixAll={fixAll}
            isFetching={isFetching}
          />
        )}

        <form
          className={styles.form}
          onSubmit={e => {
            e.preventDefault()
            handleSubmit(promptText, 'formSubmit')
          }}
        >
          {promptImage && (
            <div role="toolbar" aria-label="Attachments" className={styles.attachmentToolbar}>
              <Token text={promptImage.name} leadingVisual={ImageIcon} onRemove={handleImageRemove} size="large" />
            </div>
          )}
          <div className={styles.inputContainer}>
            {attachedErrors.length > 0 && (
              <div className={styles.attachmentsContainer}>
                {attachedErrors.length > 0 && (
                  <div className={styles.attachment}>
                    <BugIcon size={12} className={'fgColor-danger'} />
                    <span>All errors</span>
                    <IconButton
                      size="small"
                      variant="invisible"
                      aria-label="Remove errors"
                      icon={XIcon}
                      onClick={() => attachAll(false)}
                    />
                  </div>
                )}
              </div>
            )}
            <textarea
              autoFocus
              id="iterate-modal-input"
              ref={promptInputRef}
              className={styles.textarea}
              rows={1}
              placeholder="What do you want to change?"
              value={promptText}
              onChange={e => setPromptText(e.target.value)}
              onKeyDown={handleKeyDown}
              disabled={isFetching}
            />

            <div className={styles.inputFooter}>
              <div className={styles.inputActions}>
                <IconButton
                  aria-label={isFetching ? 'Add attachment (disabled)' : 'Add attachment'}
                  aria-disabled={isFetching}
                  icon={PaperclipIcon}
                  variant="invisible"
                  ref={attachImageButtonRef}
                  disabled={isFetching}
                  onClick={() => imagesInputRef.current?.click()}
                />
                <input
                  id="image-uploader"
                  hidden
                  ref={imagesInputRef}
                  type="file"
                  accept={['image/jpeg', 'image/png', 'image/webp'].join(',')}
                  onChange={attachImage}
                />

                {isFetching ? (
                  <IconButton
                    className={styles.stopButton}
                    aria-label="Stop current generation"
                    icon={SquareFillIcon}
                    variant="invisible"
                    onClick={e => {
                      e.preventDefault()
                      e.stopPropagation()
                      cancelPrompt()
                    }}
                  />
                ) : (
                  <IconButton aria-label="Send now" icon={PaperAirplaneIcon} variant="invisible" type="submit" />
                )}
              </div>
            </div>
          </div>
        </form>
      </div>
    </ReadOnlyProvider>
  )
}

export default IteratePanel

interface ActivityLogProps {
  previousRefinements: Iteration[]
  activeRefinement: Iteration
  onSelectRefinement: (v: number) => void
  filterExplanationContent: string | null
}

const ActivityLog = ({
  activeRefinement,
  previousRefinements,
  onSelectRefinement,
  filterExplanationContent,
}: ActivityLogProps) => {
  const [openActivity, setOpenActivity] = useState<boolean>(true)

  const displayItems = useMemo(() => {
    return buildDisplayRefinements(activeRefinement, previousRefinements)
  }, [activeRefinement, previousRefinements])

  const lastRefinementId = useMemo(
    () => [...displayItems].reverse().find(item => item.type === 'refinement')?.refinement.id,
    [displayItems],
  )

  return (
    <div className={styles.activityLogContainer}>
      <Timeline>
        {displayItems.map((item, i) => {
          if (item.type === 'refinement') {
            const {refinement} = item
            const isActiveRefinement = activeRefinement && refinement.id === activeRefinement.id
            const isLastRefinement = lastRefinementId === refinement.id

            return (
              <Timeline.Item
                condensed
                key={refinement.id || `generating-refinement-${i}`}
                className={clsx('ml-1', {
                  [styles.lastTimelineItem]: isLastRefinement,
                  [styles.firstTimelineItem]: i === 0,
                })}
              >
                <Timeline.Badge className={styles.timelineBadge}>
                  <DotFillIcon className={clsx({'fgColor-accent': isActiveRefinement})} />
                </Timeline.Badge>
                <Timeline.Body>
                  {isActiveRefinement ? (
                    <ActiveRefinementEntry
                      refinement={refinement}
                      isLastRefinement={isLastRefinement}
                      filterExplanationContent={filterExplanationContent}
                      openActivity={openActivity}
                      setOpenActivity={setOpenActivity}
                    />
                  ) : (
                    <DormantRefinementEntry refinement={refinement} onSelectRefinement={onSelectRefinement} />
                  )}
                </Timeline.Body>
              </Timeline.Item>
            )
          } else if (item.type === 'skip') {
            const skippedRefinements = item.skippedRefinements
            return (
              <div key={skippedRefinements[0]!.id} className={styles.skippedActivityContainer}>
                <AgentSkippedActivity skippedRefinements={skippedRefinements} onSelectRefinement={onSelectRefinement} />
              </div>
            )
          }
        })}
      </Timeline>
    </div>
  )
}

const ActiveRefinementEntry = ({
  refinement,
  isLastRefinement,
  filterExplanationContent,
  openActivity,
  setOpenActivity,
}: {
  refinement: Iteration
  isLastRefinement: boolean
  filterExplanationContent: string | null
  openActivity: boolean
  setOpenActivity: (v: boolean) => void
}) => {
  return (
    <div className={clsx(styles.activityItem, styles.activityItemActive)}>
      {refinement.iteration_type === 'ai' ? (
        <p className={clsx(styles.refinement, styles.refinementActive)}>{refinement.prompt}</p>
      ) : (
        <Label className="mb-2" variant="secondary">
          Manual edit
        </Label>
      )}
      {filterExplanationContent ? (
        <Banner
          className={styles.alertBanner}
          variant="warning"
          title="Prompt filtered"
          description={filterExplanationContent}
          hideTitle
        />
      ) : (
        <AgentActivity
          refinement={refinement}
          isLastRefinement={isLastRefinement}
          isExpanded={openActivity}
          onExpandedChange={setOpenActivity}
        />
      )}
    </div>
  )
}

const DormantRefinementEntry = ({
  onSelectRefinement,
  refinement,
}: {
  onSelectRefinement: (v: number) => void
  refinement: Iteration
}) => {
  const {isFetching} = useWorkbenchContext()
  const {isNavigatingHistory} = useIterationHistory()
  const readOnly = useReadOnly()
  return (
    <button
      onClick={() => {
        if (refinement.id) {
          onSelectRefinement(refinement.id)
        }
      }}
      className={clsx(styles.activityItem)}
      disabled={readOnly || isFetching || isNavigatingHistory || !!refinement.error}
    >
      {refinement.iteration_type === 'ai' ? (
        <p className={clsx(styles.refinement)}>{refinement.prompt}</p>
      ) : (
        <Label variant="secondary">Manual edit</Label>
      )}
    </button>
  )
}

const AgentSkippedActivity = ({
  skippedRefinements,
  onSelectRefinement,
}: {
  skippedRefinements: Iteration[]
  onSelectRefinement: (v: number) => void
}) => {
  const [isExpanded, setIsExpanded] = useState<boolean>(false)

  const handleExpand = () => setIsExpanded(!isExpanded)

  return (
    <>
      <button
        onClick={() => handleExpand()}
        className={clsx(styles.buttonNaked, styles.skippedCaption)}
        aria-expanded={isExpanded}
      >
        <div className={styles.chevron} data-expanded={isExpanded}>
          <ChevronRightIcon size={12} />
        </div>
        <span className="text-small">
          {skippedRefinements.length === 1 ? '1 ignored version' : `${skippedRefinements.length} ignored versions`}
        </span>
      </button>
      {isExpanded && (
        <div className={styles.skippedContainer}>
          {skippedRefinements.map(refinement => {
            return (
              <DormantRefinementEntry
                key={refinement.id}
                onSelectRefinement={onSelectRefinement}
                refinement={refinement}
              />
            )
          })}
        </div>
      )}
    </>
  )
}

type DisplayItem = {type: 'refinement'; refinement: Iteration} | {type: 'skip'; skippedRefinements: Iteration[]}

// TODO: this should really have a set of unit tests
const buildDisplayRefinements = (activeRefinement: Iteration, allRefinements: Iteration[]): DisplayItem[] => {
  const refinementMap = new Map(allRefinements.map(r => [r.id, r]))

  // build lineage from active to root
  const orderedAllRefinements = [...allRefinements].reverse()
  const lineage: Iteration[] = []

  for (let ptr: Iteration | undefined = activeRefinement; ptr; ) {
    lineage.push(ptr)
    ptr = ptr.parentId ? refinementMap.get(ptr.parentId) : undefined
  }
  const displayItems: DisplayItem[] = []

  let i = 0
  let j = 0
  for (; i < orderedAllRefinements.length; ) {
    const currRef = orderedAllRefinements[i]
    if (currRef?.id !== lineage[j]?.id && j === 0) {
      displayItems.push({type: 'refinement', refinement: currRef!})
      i++
    } else if (currRef?.id === lineage[j]?.id) {
      displayItems.push({type: 'refinement', refinement: currRef!})
      i++
      j++
    } else {
      const skippedRefinements: Iteration[] = []
      for (; i < orderedAllRefinements.length && orderedAllRefinements[i]?.id !== lineage[j]?.id; i++) {
        const ref = orderedAllRefinements[i]
        if (ref) skippedRefinements.push(ref)
      }
      if (skippedRefinements.length) {
        displayItems.push({type: 'skip', skippedRefinements: skippedRefinements.reverse()})
      }
    }
  }

  return displayItems.reverse()
}

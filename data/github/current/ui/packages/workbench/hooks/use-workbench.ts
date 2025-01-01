import {CopilotAuthTokenProvider} from '@github-ui/copilot-auth-token'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useNavigate} from '@github-ui/use-navigate'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {useCallback, useEffect, useMemo, useRef} from 'react'

import {useContentFilter} from '../contexts/ContentFilterContext'
import {useFilesContext} from '../contexts/FilesContext'
import {useFileSyncerContext} from '../contexts/FileSyncerContext'
import {useIterationHistory} from '../contexts/IterationHistoryContext'
import {useServerEvents} from '../contexts/ServerEventsContext'
import {useUserPromptContext} from '../contexts/UserPromptContext'
import {initialDescription, initialName, useWorkbenchContext} from '../contexts/WorkbenchContext'
import {useWorkbenchEditorAppContext} from '../contexts/WorkbenchEditorAppContext'
import {useWorkbenchStore} from '../contexts/WorkbenchStoreContext'
import {useAnalytics} from '../telemetry/use-analytics'
import type {FileDescription} from '../types/spark-history-types'
import type {Iteration, Workbench, WorkbenchRoutePayload} from '../types/workbench-types'
import {SparkAuthTokenProvider} from '../utilities/auth-token-provider'
import {USER_EDIT_COMMIT_MESSAGE} from '../utilities/commit-messages'
import {setSubmitTimestamp} from '../utilities/copilot-chat'
import {type FileStreamEvent, FileStreamEventType, generateTitle, type Step} from '../utilities/generate-iteration'
import {createRetryWithBackoff} from '../utilities/retry-with-backoff'
import {Service} from '../utilities/workbench-store-reducer'
import {useFetchFromCodespaceApi} from './use-fetch-from-codespace-api'
import {useFileUpdates} from './use-file-updates'
import {useStableCallback} from './use-stable-callback'

export interface UseWorkbenchProps {
  workbench: Workbench
  apiURL: string
  authTokenProvider: CopilotAuthTokenProvider
}

interface LocationAttachment {
  filePath: string
  startLine: number
  startColumn: number
  endLine: number
  endColumn: number
}

export interface Attachments {
  errors?: Array<{message: string}>
  locations?: LocationAttachment[]
}

export interface IterateResult {
  success: boolean
  error?: Error
}

const MAX_PROMPT_ATTEMPTS = 3

export type RepositoryVisibility = 'public' | 'private' // TODO: we'll want to support internal visibility at some point

export interface UseWorkbenchReturn {
  id: string
  updatedAt: string | undefined
  suggestions: string[]
  name: string
  description: string
  isFetching: boolean
  runtimePermanentName: string
  friendlyName: string
  repositoryUrl: string | undefined
  submitPrompt: (
    prompt: string,
    step: Step,
    method?: string,
    shouldReplace?: boolean,
    attachments?: Attachments,
  ) => Promise<IterateResult> | undefined
  cancelPrompt: () => Promise<void> | undefined
  updatePartialWorkbench: (workbench: Partial<Workbench>) => Promise<Workbench>
  workbench: Workbench
  deployUrl?: string
  persistUserEdit: (message: string, path: string) => Promise<void>
  setIsMobileSidebarOpen: (open: boolean) => void
  isMobileSidebarOpen: boolean
  createRepository: (repositoryName: string, visibility: RepositoryVisibility) => Promise<void> | undefined
  updateRefinementAndFiles: (refinementId: number | undefined) => Promise<void> | undefined
}

const FILES_THAT_DISPLAY_WHEN_STREAMED: Record<string, boolean> = {
  'index.html': true,
  'src/App.tsx': true,
  'src/index.css': true,
  'prd.md': true,
}

const initialSuggestions: string[] = []

// Custom event emitter for streaming progress updates
export const fileStreamEvents = {
  listeners: new Map<string, Array<(data: unknown) => void>>(),
  emit(event: string, data: unknown) {
    const eventListeners = this.listeners.get(event) || []
    for (const listener of eventListeners) {
      listener(data)
    }
  },
  on(event: string, callback: (data: unknown) => void) {
    if (!this.listeners.has(event)) {
      this.listeners.set(event, [])
    }
    this.listeners.get(event)?.push(callback)
    return () => {
      const eventListeners = this.listeners.get(event) || []
      const index = eventListeners.indexOf(callback)
      if (index !== -1) {
        eventListeners.splice(index, 1)
      }
    }
  },
}

export function useWorkbench(): UseWorkbenchReturn {
  const {
    workbench,
    copilot: {apiURL, ssoOrganizations},
  } = useRoutePayload<WorkbenchRoutePayload>()
  const {previousRefinements, setPreviousRefinements, setCurrentRefinement, currentRefinementId} = useIterationHistory()
  const {setIsFilteredModalOpen, setFilteredCategories, updateFilterExplanationContent, clearFilterExplanationContent} =
    useContentFilter()
  const {applyEdit} = useFileUpdates()

  const fileContentsRef = useRef<Record<string, string>>({})
  const {getFileList} = useFilesContext()

  const navigate = useNavigate()
  const {
    getFileSyncerV2,
    fileSyncerStarted,
    forceFileTreeRefresh,
    forceContentRefresh,
    fileContentsRef: fileSyncerFileContentsRef,
  } = useFileSyncerContext()
  const lineProcessingQueue = useRef<Map<string, string[]>>(new Map())
  const suggestionsBuilder = useRef<string[]>(initialSuggestions)
  const processingFiles = useRef<Set<string>>(new Set())
  const abortControllerRef = useRef<AbortController | null>(null)
  const {blobService} = useWorkbenchEditorAppContext()
  const {fetchFromCodespaceApi} = useFetchFromCodespaceApi()
  const {isServerConnected} = useServerEvents()
  const sendEvent = useAnalytics()
  const {onError} = useWorkbenchStore()

  const {
    id,
    updatedAt,
    setUpdatedAt,
    name,
    setName,
    description,
    setDescription,
    deployUrl,
    setDeployUrl,
    repositoryUrl,
    setRepositoryUrl,
    runtimePermanentName,
    friendlyName,
    setFriendlyName,
    isFetching,
    setIsFetching,
    isOptimisticLoading,
    setIsOptimisticLoading,
    isMobileSidebarOpen,
    setIsMobileSidebarOpen,
    isLoadingFromModel,
    setIsLoadingFromModel,
    initialPromptSubmitted,
    setIterationStartTime,
    sparkFileUrl,
    sparkAgentModel,
  } = useWorkbenchContext()

  const {promptText, setPromptText, promptImage, clearImageAttachment, setPromptImage} = useUserPromptContext()

  const authTokenProvider = useMemo(() => {
    if (copilotFeatureFlags.sparkAuthTokenEndpoint) {
      return new SparkAuthTokenProvider(ssoOrganizations.map(org => org.id))
    } else {
      return new CopilotAuthTokenProvider(ssoOrganizations.map(org => org.id))
    }
  }, [ssoOrganizations])

  const {snapshotUploadUri} = useRoutePayload<WorkbenchRoutePayload>()

  const getContentOfAllCurrentFiles = async () => {
    const currentFilesContents: Record<string, FileDescription> = {}
    if (fileSyncerStarted) {
      const fileSyncer = getFileSyncerV2()
      if (fileSyncer) {
        for (const file of getFileList()) {
          const contents: FileDescription = {
            content: (await fileSyncer?.readFileString(file.path)) || '',
            fileName: file.path,
          }
          currentFilesContents[file.path] = contents
        }
      }
    }
    return currentFilesContents
  }

  const suggestions = useMemo(() => {
    const currentRefinement = previousRefinements.find(ref => ref.id === currentRefinementId)
    return currentRefinement?.suggestions || suggestionsBuilder.current
  }, [currentRefinementId, previousRefinements])

  const saveWorkbenchState = useStableCallback(
    async (files: Record<string, FileDescription>, refinements: Iteration[], modelSuggestions: string[]) => {
      const updatedWorkbench = {
        files,
        previousRefinements: refinements,
        suggestions: modelSuggestions,
        shouldGenerateInitialPrompt: false,
      }

      await verifiedFetchJSON(`/copilot/spark/workbench/${workbench.id}`, {
        method: 'POST',
        body: updatedWorkbench,
      })
    },
  )

  const saveIteration = useStableCallback(async (iteration: Iteration) => {
    const response = await verifiedFetchJSON(`/copilot/spark/workbench/${workbench.id}/iterations`, {
      method: 'POST',
      body: {
        iteration: {
          prompt: iteration.prompt,
          iteration_type: iteration.iteration_type,
          suggestions: iteration.suggestions,
          sha: iteration.sha,
          files: iteration.files,
        },
      },
    })
    return await response.json()
  })

  const updatePartialWorkbench = async (partialWorkbench: Partial<Workbench>) => {
    const res = await verifiedFetchJSON(`/copilot/spark/workbench/${workbench.id}`, {
      method: 'POST',
      body: partialWorkbench,
    })
    if (!res.ok) return

    const savedWorkbench = await res.json()

    setUpdatedAt(savedWorkbench.updatedAt)

    if (partialWorkbench.name) {
      setName(savedWorkbench.name)
      setFriendlyName(savedWorkbench.friendlyName)
    }
    if (partialWorkbench.description) setDescription(savedWorkbench.description)
    if (partialWorkbench.deployUrl) setDeployUrl(savedWorkbench.deployUrl)

    // Friendly name may be updated by server whether we set it or not, so just update it
    setFriendlyName(savedWorkbench.friendlyName)
    return savedWorkbench
  }

  const updateIteration = useCallback(
    async (iteration: Iteration) => {
      const response = await verifiedFetchJSON(`/copilot/spark/workbench/${workbench.id}/iterations/${iteration.id}`, {
        method: 'PATCH',
        body: {
          iteration: {
            sha: iteration.sha,
            files: iteration.files,
          },
        },
      })
      return await response.json()
    },
    [workbench.id],
  )

  const updateRefinementAndFiles = useCallback(
    async (refinementId: number | undefined) => {
      const refinement = previousRefinements.find(ref => ref.id === refinementId)
      if (!refinement) {
        return
      }
      if (refinement.id === currentRefinementId) {
        return
      }

      if (refinement.sha) {
        const fileSyncer = getFileSyncerV2()
        if (fileSyncer && fileSyncerStarted) {
          // If the current iteration is an open user edit, we need to create a commit
          // before we switch to another iteration/commit.
          const currentRefinement = previousRefinements.find(ref => ref.id === currentRefinementId)
          if (currentRefinement?.iteration_type === 'user' && !currentRefinement.sha && !currentRefinement.id) {
            const response = await fileSyncer.createCommit(USER_EDIT_COMMIT_MESSAGE, snapshotUploadUri)
            if (response.sha) {
              // TODO: Add error handling for if updateIteration fails?
              const saved = await saveIteration({
                ...currentRefinement,
                sha: response.sha,
              })
              setPreviousRefinements(prev => prev.map(ref => (ref.id === currentRefinementId ? saved.iteration : ref)))
            }
          }
          await fileSyncer.checkoutCommitish(refinement.sha)
          forceContentRefresh()
        }
      } else {
        throw new Error('Problem with history feature flag or missing SHA')
      }

      sendEvent('reverted', {
        source: 'use-workbench.ts',
        iteration_id_origin: currentRefinementId ?? null,
        iteration_id_reverted_to: refinement.id ?? null,
        iteration_method: refinement.iteration_type,
      })

      setCurrentRefinement(refinement.id)
    },
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [
      currentRefinementId,
      fileSyncerStarted,
      forceContentRefresh,
      getFileSyncerV2,
      previousRefinements,
      setCurrentRefinement,
      setPreviousRefinements,
      snapshotUploadUri,
      updateIteration,
    ],
  )

  const updateUserEditStatus = useStableCallback(async (message: string) => {
    const fileSyncer = getFileSyncerV2()
    if (!fileSyncer || !fileSyncerStarted) {
      return
    }
    const statusResults = await fileSyncer.getGitStatus()
    const currentRefinement = previousRefinements.find(ref => ref.id === currentRefinementId)

    if (!currentRefinement || currentRefinement.iteration_type !== 'user' || currentRefinement.sha) {
      const updatedRefinement: Iteration = {
        prompt: message,
        iteration_type: 'user',
        parentId: currentRefinementId || undefined,
        files: statusResults,
      }
      setPreviousRefinements(prev => [...prev, updatedRefinement])
      setCurrentRefinement(updatedRefinement.id)
    } else {
      // If there are no file changes, but we had an in-progress user edit, remove it.
      if (Object.keys(statusResults).length === 0) {
        setPreviousRefinements(prev => prev.filter(ref => ref.id !== currentRefinementId))
        setCurrentRefinement(currentRefinement.parentId || undefined)
        return
      }

      // If the user is editing an existing user iteration, we need to update the files
      const updatedRefinement = {
        ...currentRefinement,
        files: statusResults,
      }
      setPreviousRefinements(prev => {
        const newPreviousRefinements = [...prev]
        const currentRefinementIndex = prev.findIndex(ref => ref.id === currentRefinementId)
        newPreviousRefinements[currentRefinementIndex] = updatedRefinement
        return newPreviousRefinements
      })
    }
  })

  const persistUserEdit = async (message: string, path: string) => {
    if (copilotFeatureFlags.updateUserEditStatus) {
      await updateUserEditStatus(message)
      return
    }
    const currentRefinement = previousRefinements.find(ref => ref.id === currentRefinementId)
    if (currentRefinement && currentRefinement.iteration_type === 'user' && !currentRefinement.sha) {
      // User edit has not yet been committed, but is persisted as an iteration.
      // If the user is editing the initial file again, we can bail.
      if (currentRefinement.files && currentRefinement.files[path]) {
        return
      }

      const nextCurrentRefinement: Iteration = {
        ...currentRefinement,
        files: {
          ...currentRefinement.files,
          [path]: {
            editType: 'update',
            fileName: path,
          },
        },
      }

      // User is editing more than one file, so let's update the file statuses.
      setPreviousRefinements(prev => {
        const newPreviousRefinements = [...prev]
        const currentRefinementIndex = prev.findIndex(ref => ref.id === currentRefinementId)
        newPreviousRefinements[currentRefinementIndex] = nextCurrentRefinement
        return newPreviousRefinements
      })

      await updateIteration(nextCurrentRefinement)
      return
    }

    const iteration: Iteration = {
      prompt: message,
      iteration_type: 'user',
      parentId: currentRefinementId || undefined,
      files: {
        [path]: {
          editType: 'update',
          fileName: path,
        },
      },
    }
    const responseJson = await saveIteration(iteration)
    const persisted = {...iteration, ...responseJson.iteration}
    const newPreviousRefinements = [...previousRefinements, persisted]
    setPreviousRefinements(newPreviousRefinements)
    setCurrentRefinement(persisted.id)
  }

  const persistCommit = async (message: string) => {
    const fileSyncer = getFileSyncerV2()
    let sha = ''
    if (fileSyncer && fileSyncerStarted) {
      const response = await fileSyncer.createCommit(message, snapshotUploadUri)
      sha = response.sha || ''
    }
    if (sha !== '') {
      const iteration = previousRefinements[previousRefinements.length - 1] as Iteration
      const newIteration = {
        ...iteration,
        sha,
      }
      const responseJson = await saveIteration(newIteration)
      const persisted = {...newIteration, ...responseJson.iteration}
      newIteration.id = persisted.id
      const newPreviousRefinements = [...previousRefinements]
      newPreviousRefinements[newPreviousRefinements.length - 1] = newIteration
      setPreviousRefinements(newPreviousRefinements)
      const workbenchUpdates = {
        previousRefinements: newPreviousRefinements,
      }
      updatePartialWorkbench(workbenchUpdates)
      setCurrentRefinement(newIteration.id)
    }
  }

  // Process lines from queue with a delay between each line
  const processNextLineInQueue = useStableCallback(async (fileName: string) => {
    if (!lineProcessingQueue.current.has(fileName) || lineProcessingQueue.current.get(fileName)?.length === 0) {
      processingFiles.current.delete(fileName)
      const queueIsEmpty = Array.from(lineProcessingQueue.current.values()).every(lines => lines.length === 0)
      if (!isLoadingFromModel && queueIsEmpty) {
        setIsFetching(false)
        setTimeout(async () => {
          persistCommit(`Generated by Spark`)
        }, 750) // Delay to allow for any final lines to be synced up to the Codespace
      }
      return
    }

    const lines = lineProcessingQueue.current.get(fileName) || []
    const nextLine = lines.shift()

    if (nextLine !== undefined) {
      const currentContent = fileContentsRef.current[fileName] || ''
      const newContent = currentContent + nextLine
      fileContentsRef.current[fileName] = newContent

      const result = await blobService.getBlob(fileName, workbench.id)
      const originalContent = result.ok ? result.payload?.blobContents : ''

      // We need to check if the file is still in the queue.
      // This may seem redundant, but it's possible that the file was removed
      // from the queue while we were waiting for the original content.
      if (!lineProcessingQueue.current.has(fileName)) {
        processingFiles.current.delete(fileName)
        return
      }

      // Apply the current line to the file
      await applyEdit(fileName, newContent, originalContent)

      // Schedule next line processing with a small delay
      setTimeout(
        () => {
          processNextLineInQueue(fileName)
        },
        FILES_THAT_DISPLAY_WHEN_STREAMED[fileName] ? 100 : 200,
      ) // Faster for visible files
    } else {
      processingFiles.current.delete(fileName)
    }
  })

  // Queue lines for processing
  const queueLinesForProcessing = useStableCallback((fileName: string, line: string) => {
    if (!lineProcessingQueue.current.has(fileName)) {
      lineProcessingQueue.current.set(fileName, [])
    }

    // Add lines to the queue
    const currentLines = lineProcessingQueue.current.get(fileName) || []
    currentLines.push(line)
    lineProcessingQueue.current.set(fileName, currentLines)

    // Start processing if not already in progress
    if (!processingFiles.current.has(fileName)) {
      processingFiles.current.add(fileName)
      processNextLineInQueue(fileName)
    }
  })

  /**
   * handleStreamEvent takes the streaming events from the server and updates the state of the workbench by:
   * - Adding new lines of code into the Editor state one at a time
   * - Persisting the state of the workbench (current files, refinements, and suggestions) to the server
   */
  const handleStreamEvent = useStableCallback(async (event: FileStreamEvent) => {
    switch (event.type) {
      case FileStreamEventType.NEW_FILE:
        fileContentsRef.current[event.fileName] = ''
        if (FILES_THAT_DISPLAY_WHEN_STREAMED[event.fileName]) {
          navigate(sparkFileUrl({sparkId: workbench.id, path: event.fileName}))
          forceFileTreeRefresh()
        }
        break

      case FileStreamEventType.FILE_CONTENT_CHUNK:
        queueLinesForProcessing(event.fileName, event.chunk)
        break
      case FileStreamEventType.SELF_REFINEMENT: {
        // Add suggestions, cap suggestions to a max of 3, clear out any initialSuggestions
        const filteredSuggestions = suggestionsBuilder.current.filter(
          suggestion => !initialSuggestions.includes(suggestion),
        )
        suggestionsBuilder.current = [...filteredSuggestions.slice(-2), event.refinement]
        break
      }

      case FileStreamEventType.COMPLETE: {
        switch (event.finishReason) {
          case 'content_filter': {
            cancelPrompt()
            break
          }
          case undefined: {
            break
          }
          case 'stop':
          default: {
            const updatedFiles = event.files.reduce(
              (acc, file) => {
                acc[file.fileName] = file
                return acc
              },
              {} as Record<string, FileDescription>,
            )
            const currentFiles = await getContentOfAllCurrentFiles()
            const nextFileSet = {...currentFiles, ...updatedFiles}
            const lastIteration = previousRefinements[previousRefinements.length - 1] as Iteration
            const iteration = {...lastIteration, files: nextFileSet, suggestions: suggestionsBuilder.current}
            const newPreviousRefinements = [...previousRefinements]
            newPreviousRefinements[newPreviousRefinements.length - 1] = iteration
            setPreviousRefinements(newPreviousRefinements)
            setCurrentRefinement(iteration.id)
            saveWorkbenchState(nextFileSet, newPreviousRefinements, suggestionsBuilder.current)
            setIsFetching(false)
            break
          }
        }
        break
      }

      case FileStreamEventType.ERROR:
        break

      case FileStreamEventType.PROMPT_FILTERED:
        // For filtered prompts, show in the IteratePanel
        // Right now there is nothing to do here as explanations and suggestions are handled separately
        break

      case FileStreamEventType.CONTENT_FILTERED:
        // Content filtered shows in the FilteredContentModal with categories
        setIsFilteredModalOpen(true) // Open the modal when content is filtered

        if (event.filteredCategories) {
          setFilteredCategories(event.filteredCategories)
        }
        break

      case FileStreamEventType.FILTER_EXPLANATION_CHUNK:
        updateFilterExplanationContent(event.chunk)
        break
    }
  })

  // Clean up queues and processing on unmount
  useEffect(() => {
    const lineQueue = lineProcessingQueue.current
    const processingSet = processingFiles.current

    return () => {
      lineQueue.clear()
      processingSet.clear()
    }
  }, [])

  const saveInProgressEdits = useCallback(async (): Promise<{
    refinements: Iteration[]
    updatedRefinementId: number | undefined
  }> => {
    const iteration = previousRefinements.find(ref => ref.id === currentRefinementId)
    if (
      !copilotFeatureFlags.updateUserEditStatus ||
      !iteration ||
      iteration.id ||
      iteration.sha ||
      iteration.iteration_type !== 'user'
    ) {
      return {refinements: previousRefinements, updatedRefinementId: currentRefinementId}
    }
    const responseJson = await saveIteration(iteration)
    const persisted = {...iteration, id: responseJson.iteration.id, parentId: responseJson.iteration.parentId}

    const newPreviousRefinements = previousRefinements.map(ref => {
      if (ref.id === currentRefinementId) {
        return persisted
      }
      return ref
    })
    setPreviousRefinements(newPreviousRefinements)
    setCurrentRefinement(persisted.id)
    return {
      refinements: newPreviousRefinements,
      updatedRefinementId: persisted.id,
    }
  }, [currentRefinementId, previousRefinements, saveIteration, setCurrentRefinement, setPreviousRefinements])

  //**
  /* submitPrompt takes a prompt and a step (generate or refine) and generates new content from the LLM
  /* We send the current state of the file system from the Editor, along with previous prompts the user has made.
   */
  const submitPrompt = useStableCallback(
    async (
      prompt: string,
      step: Step = 'refine',
      method: string = 'unknown',
      shouldReplace: boolean = false,
      attachments?: Attachments,
    ): Promise<IterateResult> => {
      clearFilterExplanationContent()
      if (!prompt.trim() || (isFetching && !isOptimisticLoading)) return {success: true}

      abortControllerRef.current = new AbortController()
      setIsFetching(true)
      setIsLoadingFromModel(true)
      setIterationStartTime(Date.now())
      setIsOptimisticLoading(false) // we are fetching for real now
      fileContentsRef.current = {}

      const currentFiles = await getContentOfAllCurrentFiles()
      fileSyncerFileContentsRef.current = currentFiles // Store current files in the ref for animating the file edits

      const currentImage = promptImage
      const {refinements, updatedRefinementId} = await saveInProgressEdits()

      const currentSelectedIteration = updatedRefinementId
      const currentIterations = shouldReplace ? refinements.slice(0, -1) : [...refinements]
      const nextIteration: Iteration = {
        prompt,
        iteration_type: 'ai',
        parentId: updatedRefinementId,
        files: {},
      }

      // Apply optimistic update
      setPreviousRefinements([...currentIterations, nextIteration])
      setCurrentRefinement(undefined) // Falls back to latest (optimistic one)
      clearImageAttachment()

      // Store a metric for the iteration
      sendEvent('iterate_started', {
        source: 'use-workbench.ts',
        iteration_method: method,
        iteration_id: nextIteration.id ?? null,
      })

      try {
        const iterationMap = new Map(currentIterations.map(iter => [iter.id, iter]))
        const current = currentIterations.find(iter => iter.id === updatedRefinementId)

        // Traverse the iteration chain from current iteration back to root using parentId
        const chain: Iteration[] = []
        for (let iter: Iteration | undefined = current; iter; ) {
          chain.push(iter)
          iter = iter.parentId ? iterationMap.get(iter.parentId) : undefined
        }

        const previousPrompts = chain
          .reverse() // Reverse to get chronological order (root to current)
          .map(iter => iter.prompt)
          .filter(p => p !== undefined)

        let userIterationId: number | undefined

        const updateNameAndDescription = async () => {
          const needsTitle =
            step === 'generate' &&
            (!workbench.name || workbench.name === initialName) &&
            (!workbench.description || workbench.description === initialDescription)

          if (!needsTitle) return

          const {name: newName, description: newDescription} = await generateTitle({
            prompt,
            apiURL,
            authTokenProvider,
            onEvent: handleStreamEvent,
            signal: abortControllerRef.current?.signal,
            // NOTE: these are not actually needed but tied with the function's argument type
            generationType: step,
            editorState: {files: {}},
          })
          // Zero out the friendly name so that it gets regenerated on the server side based on the new name.
          await updatePartialWorkbench({name: newName, description: newDescription, friendlyName: undefined})
        }

        const iterate = async () => {
          const res = await fetchFromCodespaceApi('/iterate', {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({
              prompt,
              workbenchId: workbench.id,
              previousPrompts,
              attachments,
              snapshotUploadUri,
              imageUrl: promptImage?.url,
              userIterationId,
              shouldPersistInProgressEdits: true,
              model: sparkAgentModel,
              featureFlags: {
                commitOnDefaultBranch: copilotFeatureFlags.commitOnDefaultBranch,
                shouldPersistInProgressEdits: true,
                useStreaming: copilotFeatureFlags.sparkUseStreaming,
                useBillingHeaders: copilotFeatureFlags.sparkUseBillingHeaders,
              },
            }),
          })

          if (!res.ok) {
            throw new Error(`API request failed with status ${res.status}`)
          }

          return res
        }

        const iterateWithRetry = createRetryWithBackoff(iterate, MAX_PROMPT_ATTEMPTS)
        const updateNameAndDescriptionWithRetry = createRetryWithBackoff(updateNameAndDescription, MAX_PROMPT_ATTEMPTS)

        // intentionally ignoring `updateNameAndDescription` if it errors since it's not critical to the iteration
        const [iterateRes] = await Promise.allSettled([iterateWithRetry(), updateNameAndDescriptionWithRetry()])
        if (iterateRes.status === 'rejected') {
          throw iterateRes.reason
        }

        const res = iterateRes.value

        // update optimistic iteration with the persisted iteration ID
        const {iterationId, parentId} = await res.json()
        const nextIterations = [...currentIterations, {...nextIteration, id: iterationId, parentId}]
        setPreviousRefinements(nextIterations)
        setCurrentRefinement(iterationId)

        // Persist the new workbench state
        saveWorkbenchState(currentFiles, nextIterations, suggestions)

        return {success: true}
      } catch (err) {
        // Revert to previous state on error
        setPreviousRefinements(currentIterations)
        setCurrentRefinement(currentSelectedIteration)
        setPromptImage(currentImage)
        setIsFetching(false)
        onError({
          service: Service.RUNTIME,
        })

        const error = new Error(`Failed to submit prompt: ${err}`)

        return {success: false, error}
      } finally {
        setSubmitTimestamp()
      }
    },
  )

  const cancelPrompt = useStableCallback(async () => {
    try {
      await fetchFromCodespaceApi('/cancel', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
      })
    } catch {
      onError({
        service: Service.RUNTIME,
      })
    }

    setIsFetching(false)
    setIterationStartTime(null)
    setIsLoadingFromModel(false)
    setPromptText(previousRefinements.at(-1)?.prompt || '')

    // mark initial prompt as submitted if the user cancels
    initialPromptSubmitted.current = true
    setIsOptimisticLoading(false)
    const lastRefinement = previousRefinements[previousRefinements.length - 2] || null
    if (lastRefinement) {
      setCurrentRefinement(lastRefinement.id)
      setPreviousRefinements(previousRefinements.slice(0, -1))
      saveWorkbenchState({}, previousRefinements.slice(0, -1), suggestions)
    } else {
      setCurrentRefinement(undefined)
      setPreviousRefinements([])
      saveWorkbenchState({}, [], suggestions)
    }
  })

  const submitInitial = useCallback(async () => {
    initialPromptSubmitted.current = true
    // NOTE: we add an optimistic iteration in the `useEffect` below with the prompt
    const lastIteration = previousRefinements[previousRefinements.length - 1]
    if (!lastIteration) return

    const prompt = lastIteration.prompt
    if (!prompt) return

    const res = await submitPrompt(prompt, 'generate', 'initial_prompt', true)

    if (!res?.success) {
      setPromptText(prompt)
    }
  }, [initialPromptSubmitted, previousRefinements, setPromptText, submitPrompt])

  // Handle initial prompt
  useEffect(() => {
    if (!initialPromptSubmitted.current && workbench.shouldGenerateInitialPrompt && !isLoadingFromModel) {
      if (!currentRefinementId && promptText) {
        const refinement: Iteration = {
          prompt: promptText,
          iteration_type: 'ai',
          files: {},
        }
        setPreviousRefinements([refinement])
        setCurrentRefinement(refinement.id)
        setPromptText('')
        setIsOptimisticLoading(true)
      }

      if (isServerConnected) {
        submitInitial()
      }
    }
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isServerConnected])

  const createRepository = useStableCallback(async (repositoryName: string, visibility: RepositoryVisibility) => {
    const response = await fetchFromCodespaceApi('/publish', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        name: repositoryName,
        isPrivate: visibility === 'private',
      }),
    })
    if (!response.ok) {
      throw new Error(`Failed to create repository: ${response.statusText} (${response.status})`)
    }

    const json = await response.json()
    setRepositoryUrl(json.repository.url)
  })

  return {
    id,
    name,
    description,
    updatedAt,
    runtimePermanentName,
    friendlyName,
    suggestions,
    deployUrl,
    isFetching,
    submitPrompt,
    cancelPrompt,
    workbench,
    updatePartialWorkbench,
    persistUserEdit,
    isMobileSidebarOpen,
    setIsMobileSidebarOpen,
    createRepository,
    repositoryUrl,
    updateRefinementAndFiles,
  }
}

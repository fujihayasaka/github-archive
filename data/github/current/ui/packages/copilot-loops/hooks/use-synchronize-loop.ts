import {useEffect, useMemo, useRef} from 'react'
import {usePipesService} from '../contexts/PipesServiceProvider'
import {useGetPipesState, usePipesDispatch, usePipesStateLens} from '../contexts/PipesStateProvider'
import {isDummyPipeline} from '../example-loops/dummy-pipelines'
import type {CopilotChatState} from '@github-ui/copilot-chat/utils/copilot-chat-reducer'
import type {CopilotChatMessage} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {getLatestPipe} from '../utils/chat-helpers'
import {useAppContext} from '../contexts/AppContextProvider'
import type {Pipeline, PipelineValidationError} from '../types/app'
import {firstNodeWithValidationErrors, onlyUnfixableErrors} from '../utils/errors'
import type {ExecutionState} from '../state/pipes-state'
import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import {useParams} from 'react-router-dom'
import {useLoop} from './queries/use-loop'
import {useLoopLens} from './use-loop-lens'
import {useLoopOperations} from './use-loop-operations'
import {validatePipeline} from '../service/validate-pipeline'
import {getLoopThreadId, setLoopThreadId} from '../utils/loop-thread-storage'
import {getSelectedThread} from '@github-ui/copilot-chat/utils/get-selected-thread'

/**
 * This hook handles all synchronization between:
 * - Execution state storage
 * - The chat history
 */
export function useSynchronizeLoop(chatState: CopilotChatState) {
  useSyncThreadToLoop(chatState)
  useSyncLoopFromChat(chatState)
  useStoreExecutionState()
}

function useSyncThreadToLoop(chatState: CopilotChatState) {
  const {data: loop} = useLoop('latest')
  const manager = useChatManager()
  const selectedThread = getSelectedThread(chatState)
  const {threads, threadsLoading} = chatState
  const loopExists = !!loop
  const {loopID} = useParams<{loopID: string}>()
  const selectedThreadID = chatState.selectedThreadID

  // sync the loop's thread to chat state
  useEffect(() => {
    const handleThread = async () => {
      // if threads haven't started loading, we need to kick it off manually
      if (threadsLoading.state === 'pending') {
        manager.fetchThreads()
        return
      }

      if (!loopExists || threadsLoading.state !== 'loaded' || !loopID) return

      // Read thread ID from local storage
      const loopThreadId = getLoopThreadId(loopID)

      if (loopThreadId && selectedThread?.id !== loopThreadId) {
        // Select the loop's associated thread.
        // If the thread is gone, we just no-op and let the user create a new one if they want.
        const loopThread = threads.get(loopThreadId)
        if (loopThread) {
          await manager.selectThread(loopThread, {includeThreads: false})
        }
      }
    }

    handleThread()
  }, [loopExists, manager, selectedThread?.id, threads, threadsLoading, loopID])

  // sync chat state selected thread ID to the loop's thread ID in local storage
  useEffect(() => {
    if (!loopID || !selectedThreadID) return

    setLoopThreadId(loopID, selectedThreadID)
  }, [selectedThreadID, loopID])
}

/**
 * Whenever the latest pipeline in the chat changes, evaluate which
 * version of the pipeline should be put in the application state.
 */
function useSyncLoopFromChat(chatState: CopilotChatState) {
  const {data: loop} = useLoop()
  const dispatch = usePipesDispatch()
  const pipesService = usePipesService()
  const pipelineFromChat = useLatestPipelineFromChat(chatState.selectedThreadID, chatState.messages)
  const getPipesState = useGetPipesState()
  const {sendChatMessage} = useAppContext()
  const {updateLoop} = useLoopOperations()

  const lastHandledPipeline = useRef<Pipeline | null>(null)

  useEffect(() => {
    let cancelled = false

    const handleNewPipeline = async () => {
      const pipelineInStorage = loop
      const initializing = !pipelineInStorage || isDummyPipeline(pipelineInStorage)

      // we have two sources of loops: the current conversation and browser storage
      // just use the most recent one
      if (!pipelineFromChat && !pipelineInStorage) return
      const storedUpdatedAt = new Date(pipelineInStorage?.updatedAt ?? 0)
      const chatUpdatedAt = new Date(pipelineFromChat?.updatedAt ?? 0)
      const pipelineToUse = storedUpdatedAt >= chatUpdatedAt ? pipelineInStorage : pipelineFromChat
      if (!pipelineToUse) return

      const executionState = await pipesService.getExecutionState(pipelineToUse.id)
      if (cancelled) return

      // two conditions to run the pipeline:
      // 1. the pipeline is the same as the one in the chat - this means we just got a new one back
      // 2. there is no pipeline in the chat and no execution state - this means we are initing an example loop
      const fromChat = pipelineToUse === pipelineFromChat
      const shouldRun = fromChat || (!pipelineFromChat && !executionState)
      const shouldAutofix = shouldRun && !initializing

      if (lastHandledPipeline.current === pipelineToUse) return
      lastHandledPipeline.current = pipelineToUse

      // write the new loop from the chat to storage
      if (fromChat) updateLoop(pipelineToUse)

      const validationErrors = validatePipeline(pipelineToUse)
      if (shouldRun) {
        runAndAutofixPipeline(pipelineToUse, shouldAutofix, validationErrors)
      } else {
        restoreSavedExecutionState(executionState)
        const firstErrorNodeId = firstNodeWithValidationErrors(pipelineToUse)
        if (firstErrorNodeId) dispatch({type: 'FOCUS_NODE', nodeId: firstErrorNodeId})
      }
    }

    const restoreSavedExecutionState = async (executionState: ExecutionState | null) => {
      if (cancelled) return
      if (!executionState) return

      dispatch({type: 'RESTORE_EXECUTION_STATE', executionState})
    }

    const runAndAutofixPipeline = async (
      pipeline: Pipeline,
      autofix: boolean,
      validationErrors: PipelineValidationError[],
    ) => {
      await wait()
      if (cancelled) return

      if (onlyUnfixableErrors(validationErrors)) {
        const firstErrorNodeId = firstNodeWithValidationErrors(pipeline)
        if (firstErrorNodeId) dispatch({type: 'FOCUS_NODE', nodeId: firstErrorNodeId})

        return
      }

      if (validationErrors.length > 0 && (!shouldSkipAutoFix(chatState) || !autofix)) {
        sendChatMessage(getFixValidationErrorsMessage(validationErrors))
        return
      }

      const nodeIds = Object.keys(getPipesState().executionState.nodes)
      dispatch({type: 'CLEAR_NODE_RESULTS', pipelineId: pipeline.id, nodeIds})

      await wait()
      if (cancelled) return

      const iteration = getPipesState().executionState.iteration
      await pipesService.runPipeline(pipeline, iteration, dispatch)
      if (cancelled) return

      await wait()
      if (cancelled) return

      const errorsFromRun = Object.entries(getPipesState().executionState.nodes)
        .filter(([_, nodeState]) => !!nodeState.error)
        .map(([nodeId, nodeState]) => ({nodeId, error: nodeState.error}))

      if (errorsFromRun.length > 0 && (!shouldSkipAutoFix(chatState) || !autofix)) {
        sendChatMessage(getPipelineRunErrorsMessage(errorsFromRun))
        return
      }
    }

    handleNewPipeline()
    return () => {
      cancelled = true
    }

    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pipelineFromChat, dispatch, pipesService])
}

/**
 * For the purpose of only storing *new* pipelines, we want to have each
 * pipeline generated by the chat always be the same object. However, getLatestPipe
 * sanitizes the pipeline, which creates a new object. We know that the
 * chat messages do not change after they are sent, so a pipeline created
 * as part of a given message is always the same. This means we can safely
 * memoize on the message ID and ignore the linter.
 */
function useLatestPipelineFromChat(selectedThreadId: string | null, messages: readonly CopilotChatMessage[]) {
  const {loopID} = useParams()
  const {pipeline, messageId} = getLatestPipe(selectedThreadId, messages) ?? {}

  // eslint-disable-next-line react-hooks/react-compiler
  // eslint-disable-next-line react-hooks/exhaustive-deps
  return useMemo(() => (loopID && pipeline ? {...pipeline, id: loopID} : pipeline), [messageId, loopID])
}

/**
 * Whenever the execution state updates, save it
 */
function useStoreExecutionState() {
  const pipesService = usePipesService()
  const execution = usePipesStateLens(s => s.executionState)
  const loopID = useLoopLens(loop => loop?.id)

  useEffect(() => {
    if (!loopID) return
    pipesService.updateExecutionState(loopID, execution.iteration, execution)
  }, [loopID, execution, pipesService])
}

const validationErrorMessageStart = 'The following errors were found in the Loop configuration:'
const runtimeErrorMessageStart = 'The following errors were found while running the Loop:'

function getFixValidationErrorsMessage(validationErrors: PipelineValidationError[]): string {
  return `${validationErrorMessageStart}

${validationErrors.map(getValidationErrorText)}

Fix the Loop by modifying its nodes to resolve these errors.`
}

function getValidationErrorText(err: PipelineValidationError): string {
  return `- ${err.error} (Nodes ${err.involvedNodes.join(', ')})`
}

function getPipelineRunErrorsMessage(errors: Array<{nodeId: string; error?: string}>): string {
  return `${runtimeErrorMessageStart}

${errors.map(getPipelineRunErrorText)}

Fix the Loop by modifying its nodes to resolve these errors.`
}

function getPipelineRunErrorText(err: {nodeId: string; error?: string}): string {
  return `- ${err.error} (Node ${err.nodeId})`
}

async function wait() {
  return new Promise(resolve => setTimeout(resolve, 10))
}

const retryLimit = 2

/**
 * This is a bit of a hack. This prevents an infinite loop of fixing by
 * checking if the last N user messages are all the same kind of
 * autofix message. If so, we won't send another one.
 */
function shouldSkipAutoFix(chatState: CopilotChatState): boolean {
  const lastThreeUserMessages = chatState.messages
    .toReversed()
    .filter(m => m.role === 'user')
    .slice(0, retryLimit)
  if (lastThreeUserMessages.length < retryLimit) return false

  return (
    lastThreeUserMessages.every(m => m.content?.startsWith(validationErrorMessageStart)) ||
    lastThreeUserMessages.every(m => m.content?.startsWith(runtimeErrorMessageStart))
  )
}

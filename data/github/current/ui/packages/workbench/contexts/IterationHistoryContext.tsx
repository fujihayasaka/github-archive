import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {createContext, useContext, useEffect, useMemo, useRef, useState} from 'react'

import {useStableCallback} from '../hooks/use-stable-callback'
import type {Iteration, WorkbenchRoutePayload} from '../types/workbench-types'
import {USER_EDIT_COMMIT_MESSAGE} from '../utilities/commit-messages'
import {useFileSyncerContext} from './FileSyncerContext'
import {useWorkbenchContext} from './WorkbenchContext'

export type IterationHistoryContext = {
  setCurrentRefinement: (refinementId: number | undefined, saveToLocalStorage?: boolean) => void
  previousRefinements: Iteration[]
  setPreviousRefinements: (value: Iteration[] | ((prev: Iteration[]) => Iteration[])) => void
  currentRefinementId: number | undefined
  isNavigatingHistory: boolean
  setIsNavigatingHistory: (value: boolean) => void
}

const POLL_FOR_USER_EDITS_INTERVAL = 15 * 1000 // Poll every 15 seconds
type PollingStateData = {
  previousRefinements: Iteration[]
  currentRefinementId: number | undefined
  fileSyncerStarted: boolean
  isFetching: boolean
}

export function IterationHistoryProvider({children}: {children: React.ReactNode}) {
  const {workbench} = useRoutePayload<WorkbenchRoutePayload>()

  const [previousRefinements, setPreviousRefinements] = useState<Iteration[]>(workbench.previousRefinements || [])
  const initialRefinmentId = workbench.currentRefinementId ? workbench.currentRefinementId : undefined
  const [currentRefinementId, setCurrentRefinementId] = useState<number | undefined>(initialRefinmentId)
  const [isNavigatingHistory, setIsNavigatingHistory] = useState(false)
  const {getFileSyncerV2, fileSyncerStarted} = useFileSyncerContext()
  const pollForUserEditsInterval = useRef<ReturnType<typeof setInterval> | undefined>(undefined)
  const {isFetching} = useWorkbenchContext()
  // Using a ref here since we're scheduling an interval that needs to access the latest state
  // without causing re-renders.
  const pollingStateRef = useRef<PollingStateData>({
    previousRefinements,
    currentRefinementId,
    fileSyncerStarted,
    isFetching,
  })

  const setCurrentRefinement = useStableCallback((refinementId: number | undefined) => {
    setCurrentRefinementId(refinementId)
  })

  pollingStateRef.current = {
    previousRefinements,
    currentRefinementId,
    fileSyncerStarted,
    isFetching,
  }

  useEffect(() => {
    if (!copilotFeatureFlags.updateUserEditStatus) {
      return
    }

    async function initializeUserStatus() {
      const {
        previousRefinements: prevRefinements,
        currentRefinementId: refinementId,
        fileSyncerStarted: isFileSyncerStarted,
        isFetching: isGenerating,
      } = pollingStateRef.current

      if (isGenerating) {
        // If a generation is in progress, we don't want to poll for user edits
        return
      }

      const fileSyncer = getFileSyncerV2()
      if (!fileSyncer || !isFileSyncerStarted) {
        return
      }
      const statusResults = await fileSyncer.getGitStatus()
      const currentRefinement = prevRefinements.find(ref => ref.id === refinementId)
      const hasInProgreessUserEdit =
        currentRefinement && currentRefinement.iteration_type === 'user' && !currentRefinement.sha

      if (Object.keys(statusResults).length <= 0) {
        // Check if we had an in progress user edit, if so, we need to clear it
        if (hasInProgreessUserEdit) {
          setPreviousRefinements(prev => prev.filter(ref => ref.id !== refinementId))
          setCurrentRefinement(currentRefinement.parentId || undefined)
        }
        return
      }

      if (!hasInProgreessUserEdit) {
        const updatedRefinement: Iteration = {
          prompt: USER_EDIT_COMMIT_MESSAGE,
          iteration_type: 'user',
          parentId: refinementId || undefined,
          files: statusResults,
        }
        setPreviousRefinements(prev => [...prev, updatedRefinement])
        setCurrentRefinement(updatedRefinement.id)
        return
      }

      // If the user is editing an existing user iteration, we need to update the files
      const updatedRefinement = {
        ...currentRefinement,
        files: statusResults,
      }
      setPreviousRefinements(prev => {
        const newPreviousRefinements = [...prev]
        const currentRefinementIndex = prev.findIndex(ref => ref.id === refinementId)
        newPreviousRefinements[currentRefinementIndex] = updatedRefinement
        return newPreviousRefinements
      })
    }
    initializeUserStatus()
    clearInterval(pollForUserEditsInterval.current)
    pollForUserEditsInterval.current = setInterval(initializeUserStatus, POLL_FOR_USER_EDITS_INTERVAL)
    return () => {
      clearInterval(pollForUserEditsInterval.current)
    }
    // Note: disabling exhaustive deps here because we just want to schedule the interval one time.
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [fileSyncerStarted])

  const value = useMemo(
    () => ({
      setPreviousRefinements,
      setCurrentRefinement,
      previousRefinements,
      currentRefinementId,
      isNavigatingHistory,
      setIsNavigatingHistory,
    }),
    [currentRefinementId, isNavigatingHistory, previousRefinements, setCurrentRefinement],
  )
  return <IterationHistoryContext.Provider value={value}>{children}</IterationHistoryContext.Provider>
}

export const IterationHistoryContext = createContext<IterationHistoryContext | undefined>(undefined)

export function useIterationHistory() {
  const context = useContext(IterationHistoryContext)
  if (!context) {
    throw new Error('useIterationHistory must be used within an IterationHistoryProvider')
  }
  return context
}

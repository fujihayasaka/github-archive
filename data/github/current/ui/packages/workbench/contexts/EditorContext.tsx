import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useNavigate} from '@github-ui/use-navigate'
import React, {useCallback, useContext, useEffect, useMemo, useRef, useState} from 'react'

import usePrevious from '../monaco/use-previous'
import type {WorkbenchRoutePayload} from '../types/workbench-types'
import {useFilesContext} from './FilesContext'
import {useFileSyncerContext} from './FileSyncerContext'
import {useWorkbenchContext} from './WorkbenchContext'

const FILE_NAVIGATION_DELAY = 5000 // 5 seconds delay

export type EditorContext = {
  refreshEditor: boolean
  setRefreshEditor: (state: boolean) => void
  forceEditorRefresh: () => void
  isAnimating: boolean
  setIsAnimating: (isAnimating: boolean) => void
  previousPath: string | null
  setPreviousPath: (path: string | null) => void
  isNavigating: boolean
  watchingPath: string | null
  setWatchingPath: (path: string | null) => void
}

export const EditorContext = React.createContext<EditorContext | undefined>(undefined)

function currentFilePath() {
  return window.location.pathname.replace(/\/copilot\/spark\/[^/]*\/file\//, '')
}

export function EditorContextProvider({children}: React.PropsWithChildren) {
  const {path, workbench} = useRoutePayload<WorkbenchRoutePayload>()
  const {fileChangeStack, setFileChangeStack, forceContentRefresh} = useFileSyncerContext()
  const {getFileList} = useFilesContext()
  const {isFetching, sparkFileUrl} = useWorkbenchContext()
  const navigate = useNavigate()
  const previousIsFetching = usePrevious(isFetching)
  const lastNavigationTimeRef = useRef<number>(0)

  // Shows loading skeleton until content is loaded
  const [refreshEditor, setRefreshEditor] = useState(false)
  const [isAnimating, setIsAnimating] = useState(false)
  const [previousPath, setPreviousPath] = useState<string | null>(null)
  const [watchingPath, setWatchingPath] = useState<string | null>(null)

  const isNavigating = useMemo(() => path !== previousPath, [path, previousPath])

  /*
   * Forces loading skeleton to show until next content is loaded
   */
  const forceEditorRefresh = useCallback(() => {
    setRefreshEditor(true)
  }, [])

  /**
   * Handles file updates from "notifyFileChanged" events between fetching states
   */
  const handleFileChanges = useCallback(() => {
    // If we just finished fetching, clear the file change stack
    if (previousIsFetching && !isFetching) {
      setFileChangeStack([])
      return
    }

    // If we're not fetching, check if current file needs refresh
    if (!isFetching) {
      const currentPath = currentFilePath()
      const needsRefresh = fileChangeStack.some(change => change.path === currentPath)

      if (needsRefresh) {
        forceContentRefresh()
      }

      if (fileChangeStack.length > 0) {
        setFileChangeStack([])
      }
    }
  }, [isFetching, previousIsFetching, fileChangeStack, setFileChangeStack, forceContentRefresh])

  // Determine if enough time has passed since last navigation
  const shouldDelayNavigation = useCallback(() => {
    const currentTime = Date.now()
    const timeElapsed = currentTime - lastNavigationTimeRef.current
    const shouldDelay = timeElapsed < FILE_NAVIGATION_DELAY && lastNavigationTimeRef.current !== 0

    return {
      shouldDelay,
      remainingTime: shouldDelay ? FILE_NAVIGATION_DELAY - timeElapsed : 0,
    }
  }, [])

  /**
   * Navigates to the next changed file that needs attention
   */
  const navigateToNextFileChange = useCallback(() => {
    if (!isFetching) return

    // Only watch added/modified changes that exist in the file directory
    const fileList = getFileList()
    const nextFileChangeIndex = fileChangeStack.findIndex(
      change =>
        (change.changeType === 'added' || change.changeType === 'modified') &&
        fileList.find(file => file.path === change.path),
    )
    const nextFileChange = fileChangeStack[nextFileChangeIndex]
    if (!nextFileChange) return

    // Handle animation delays
    if (isAnimating) {
      const timeoutId = window.setTimeout(navigateToNextFileChange, FILE_NAVIGATION_DELAY)
      return () => clearTimeout(timeoutId)
    }

    // Handle minimum time between navigations
    const {shouldDelay, remainingTime} = shouldDelayNavigation()
    if (shouldDelay) {
      const timeoutId = window.setTimeout(navigateToNextFileChange, remainingTime)
      return () => clearTimeout(timeoutId)
    }

    setFileChangeStack(prev => prev.slice(nextFileChangeIndex + 1))

    const nextPath = nextFileChange.path

    // Handle case when file is already open
    if (currentFilePath() === nextPath) {
      setWatchingPath(nextPath)
      forceContentRefresh()
      return
    }

    navigate(sparkFileUrl({sparkId: workbench.id, path: nextPath}))
    setWatchingPath(nextPath)
  }, [
    isFetching,
    getFileList,
    fileChangeStack,
    isAnimating,
    shouldDelayNavigation,
    setFileChangeStack,
    navigate,
    sparkFileUrl,
    workbench.id,
    forceContentRefresh,
  ])

  // Track navigation completion
  useEffect(() => {
    if (previousPath && !isNavigating) {
      lastNavigationTimeRef.current = Date.now()
    }
  }, [isNavigating, previousPath])

  useEffect(() => {
    handleFileChanges()
  }, [handleFileChanges, fileChangeStack, isFetching, previousIsFetching])

  useEffect(() => {
    return navigateToNextFileChange()
  }, [navigateToNextFileChange, isFetching, fileChangeStack])

  const value = useMemo(
    () => ({
      forceEditorRefresh,
      refreshEditor,
      setRefreshEditor,
      isAnimating,
      setIsAnimating,
      previousPath,
      setPreviousPath,
      isNavigating,
      watchingPath,
      setWatchingPath,
    }),
    [forceEditorRefresh, refreshEditor, isAnimating, previousPath, isNavigating, watchingPath],
  )

  return <EditorContext.Provider value={value}>{children}</EditorContext.Provider>
}

export function useEditorContext() {
  const context = useContext(EditorContext)
  if (!context) {
    throw new Error('useEditorContext must be used within a EditorContextProvider')
  }
  return context
}

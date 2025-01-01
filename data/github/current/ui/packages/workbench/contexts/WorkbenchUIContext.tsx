import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useNavigate} from '@github-ui/use-navigate'
import {
  createContext,
  type PropsWithChildren,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from 'react'

import type {WorkbenchRoutePayload, WorkingMode} from '../types/workbench-types'
import {sparkPathRegex, useWorkbenchContext} from './WorkbenchContext'

export interface WorkbenchUIContextData {
  createRepositoryModelOpen: boolean
  setCreateRepositoryModelOpen: (value: boolean) => void
  mobileViewActive: boolean
  navigateAndViewFile: (path: string) => void
  previewBrowserRef: React.MutableRefObject<HTMLIFrameElement | null>
  previewRefreshing: boolean
  previewUrl: string | null
  refreshPreview: () => void
  setMobileViewActive: (active: boolean) => void
  setPreviewUrl: (url: string | null) => void
  setWorkingMode: (mode: WorkingMode) => void
  sidePanelOpen: boolean
  toggleSidePanel: (state?: boolean) => void
  workingMode: WorkingMode
}

const SIDE_PANEL_LS_KEY = 'spark:side-panel-open'
const WORKING_MODE_LS_KEY = 'spark:working-mode'

/**
 * Context that holds global static app state
 */
export const WorkbenchUIContext = createContext<WorkbenchUIContextData | undefined>(undefined)

const isWorkingMode = (workingMode: string): workingMode is WorkingMode => {
  return ['preview', 'code', 'split'].includes(workingMode)
}

export function WorkbenchUIContextProvider({children}: PropsWithChildren) {
  const navigate = useNavigate()
  const {workbench} = useRoutePayload<WorkbenchRoutePayload>()
  const {sparkFileUrl, sparkBaseUrl} = useWorkbenchContext()
  const shouldUseUpdatedUrls = useFeatureFlag('spark_workbench_updated_urls')

  const [createRepositoryModelOpen, setCreateRepositoryModelOpen] = useState(false)
  const [sidePanelOpen, setSidePanelOpen] = useState(true)
  const [mobileViewActive, setMobileViewActive] = useState(false)
  const previewBrowserRef = useRef<HTMLIFrameElement | null>(null)
  const [previewRefreshing, setPreviewRefreshing] = useState(false)
  const [previewUrl, setPreviewUrl] = useState<string | null>('')
  const [workingMode, setWorkingMode] = useState<WorkingMode>('preview')
  const [lastViewedFile, setLastViewedFile] = useState<string | null>(null)

  const autoSelectPathName = !shouldUseUpdatedUrls || workingMode !== 'preview'

  useEffect(() => {
    const path = window.location.pathname
    if (
      (path.startsWith('/copilot/spark') || sparkPathRegex.test(path)) &&
      !path.includes('file') &&
      autoSelectPathName
    ) {
      const file = lastViewedFile || 'src/App.tsx'
      navigate(sparkFileUrl({sparkId: workbench.id, path: file}))
      if (!lastViewedFile) {
        setLastViewedFile(file)
      }
    }
  }, [autoSelectPathName, lastViewedFile, navigate, sparkFileUrl, workbench.id])

  useEffect(() => {
    const path = window.location.pathname
    // if the path includes a file path, set it as the last viewed file
    if (path.includes('file')) {
      const filePathMatch = path.match(/file\/(.+)/)
      if (filePathMatch && filePathMatch[1]) {
        const filePath = decodeURIComponent(filePathMatch[1])
        setLastViewedFile(filePath)
      }
    }
  }, [])

  useEffect(() => {
    const storedSidePanelState = localStorage.getItem(SIDE_PANEL_LS_KEY)
    if (storedSidePanelState) {
      setSidePanelOpen(storedSidePanelState === 'true')
    }

    const storedWorkingMode = localStorage.getItem(WORKING_MODE_LS_KEY)
    if (storedWorkingMode && isWorkingMode(storedWorkingMode)) {
      setWorkingMode(storedWorkingMode)
    }
  }, [shouldUseUpdatedUrls])

  const navigateAndViewFile = useCallback(
    (path: string) => {
      setWorkingMode(workingMode === 'code' ? 'code' : 'split')
      setLastViewedFile(path)
      navigate(sparkFileUrl({sparkId: workbench.id, path}))
    },
    [navigate, sparkFileUrl, workbench?.id, workingMode],
  )

  const toggleSidePanel = useCallback(
    (state?: boolean) => {
      const newState = typeof state === 'boolean' ? state : !sidePanelOpen
      setSidePanelOpen(newState)
      localStorage.setItem(SIDE_PANEL_LS_KEY, `${newState}`)
    },
    [sidePanelOpen],
  )

  const setActiveWorkingMode = useCallback(
    (state: WorkingMode) => {
      setWorkingMode(state)
      localStorage.setItem(WORKING_MODE_LS_KEY, state)
      if (!shouldUseUpdatedUrls) {
        return
      }
      if (state === 'preview') {
        navigate(sparkBaseUrl(workbench))
      }
    },
    [navigate, shouldUseUpdatedUrls, sparkBaseUrl, workbench],
  )

  const refreshPreview = useCallback(() => {
    const url = previewBrowserRef.current?.src
    previewBrowserRef.current?.setAttribute('src', '')
    previewBrowserRef.current?.setAttribute('src', url ?? '')
    setPreviewRefreshing(true)
  }, [])

  const value = useMemo(
    () => ({
      createRepositoryModelOpen,
      setCreateRepositoryModelOpen,
      mobileViewActive,
      navigateAndViewFile,
      setMobileViewActive,
      previewBrowserRef,
      previewRefreshing,
      previewUrl,
      setPreviewUrl,
      refreshPreview,
      setWorkingMode: setActiveWorkingMode,
      sidePanelOpen,
      toggleSidePanel,
      workingMode,
    }),
    [
      createRepositoryModelOpen,
      mobileViewActive,
      navigateAndViewFile,
      previewRefreshing,
      previewUrl,
      refreshPreview,
      setActiveWorkingMode,
      sidePanelOpen,
      toggleSidePanel,
      workingMode,
    ],
  )

  return <WorkbenchUIContext.Provider value={value}>{children}</WorkbenchUIContext.Provider>
}

export function useWorkbenchUI() {
  const context = useContext(WorkbenchUIContext)
  if (!context) {
    throw new Error('useWorkbenchUI must be used within an WorkbenchUIContextProvider')
  }
  return context
}

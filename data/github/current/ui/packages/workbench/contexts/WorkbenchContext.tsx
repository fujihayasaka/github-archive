import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {encodePart} from '@github-ui/paths'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useNavigate} from '@github-ui/use-navigate'
import {useLocalStorage} from '@github-ui/use-safe-storage/local-storage'
import {createContext, useCallback, useContext, useEffect, useMemo, useRef, useState} from 'react'

import type {SparkAgentModel, Workbench, WorkbenchRoutePayload} from '../types/workbench-types'

export const sparkPathRegex = /^\/spark\/[^/]+\/[^/]+$/
export const initialName = 'New spark'
export const initialDescription = ''
export const initialDeployUrl = ''
export function WorkbenchContextProvider({children}: {children: React.ReactNode}) {
  const navigate = useNavigate()
  const {workbench} = useRoutePayload<WorkbenchRoutePayload>()
  const [name, setName] = useState<string>(workbench.name || initialName)
  const [description, setDescription] = useState<string>(workbench.description || initialDescription)
  const [updatedAt, setUpdatedAt] = useState<string | undefined>(workbench.updatedAt)
  const [deployUrl, setDeployUrl] = useState<string>(workbench.deployUrl || initialDeployUrl)
  const [repositoryUrl, setRepositoryUrl] = useState<string | undefined>(workbench.repositoryUrl)
  const [runtimePermanentName] = useState<string>(workbench.runtimePermanentName)
  const [isFetching, setIsFetching] = useState(false)
  const [isOptimisticLoading, setIsOptimisticLoading] = useState(false)
  const [friendlyName, setFriendlyName] = useState<string>(workbench.friendlyName)

  const [isLoadingFromModel, setIsLoadingFromModel] = useState(false)
  const [iterationStartTime, setIterationStartTime] = useState<number | null>(null)
  const billableOwner = workbench.billableOwner
  const shouldUseUpdatedUrls = useFeatureFlag('spark_workbench_updated_urls')
  const owner = billableOwner?.login

  const sparkBaseUrl = useCallback(
    (spark: Workbench | WorkbenchContextData) => {
      if (shouldUseUpdatedUrls && spark.billableOwner?.login && spark.friendlyName) {
        return `/spark/${spark.billableOwner?.login}/${encodeURIComponent(spark.friendlyName)}`
      }
      return `/copilot/spark/${encodeURIComponent(spark.id)}`
    },
    [shouldUseUpdatedUrls],
  )

  const sparkFileUrl = useCallback(
    ({sparkId, path}: {sparkId: string; path: string}) => {
      if (shouldUseUpdatedUrls && owner && friendlyName) {
        return `/spark/${owner}/${encodeURIComponent(friendlyName)}/file/${encodePart(path)}`
      }
      return `/copilot/spark/${encodeURIComponent(sparkId)}/file/${encodePart(path)}`
    },
    [shouldUseUpdatedUrls, owner, friendlyName],
  )

  const [userAgentModelPreference, setUserAgentModelPreference] = useLocalStorage<SparkAgentModel>(
    'spark-agent-model-preference',
    copilotFeatureFlags.workbenchDefaultSonnet4 ? 'claude-sonnet-4' : 'claude-3.7-sonnet',
  )

  const sparkAgentModel = useMemo((): SparkAgentModel => {
    // If the feature flag is enabled, return the user's model preference.
    if (copilotFeatureFlags.workbenchDefaultSonnet4) {
      return userAgentModelPreference
    } else {
      return 'claude-3.7-sonnet'
    }
  }, [userAgentModelPreference])

  const [isMobileSidebarOpen, setIsMobileSidebarOpen] = useState(false)
  const initialPromptSubmitted = useRef(false)

  // Update the URL to include the friendlyName, when we have it
  useEffect(() => {
    if (!shouldUseUpdatedUrls) return
    if (!owner || !friendlyName) {
      return
    }

    const currentPath = window.location.pathname
    const pattern = new RegExp(`/spark/${owner}/[^/]+`)
    if (pattern.test(currentPath)) {
      // Replace the matching portion with the new path containing friendlyName
      const newPath = currentPath.replace(pattern, `/spark/${owner}/${encodeURIComponent(friendlyName)}`)
      if (newPath === currentPath) return
      navigate(newPath, {replace: true})
    }
  }, [friendlyName, navigate, owner, shouldUseUpdatedUrls, workbench.id])

  const value = useMemo(() => {
    return {
      id: workbench.id,
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
      isFetching: isFetching || isOptimisticLoading,
      setIsFetching,
      isOptimisticLoading,
      setIsOptimisticLoading,
      isMobileSidebarOpen,
      setIsMobileSidebarOpen,
      isLoadingFromModel,
      setIsLoadingFromModel,
      initialPromptSubmitted,
      iterationStartTime,
      setIterationStartTime,
      userAgentModelPreference,
      setUserAgentModelPreference,
      sparkAgentModel,
      sparkFileUrl,
      sparkBaseUrl,
      billableOwner,
    }
  }, [
    workbench.id,
    updatedAt,
    name,
    description,
    deployUrl,
    repositoryUrl,
    runtimePermanentName,
    friendlyName,
    isFetching,
    isOptimisticLoading,
    isMobileSidebarOpen,
    isLoadingFromModel,
    iterationStartTime,
    setIterationStartTime,
    userAgentModelPreference,
    setUserAgentModelPreference,
    sparkAgentModel,
    sparkFileUrl,
    sparkBaseUrl,
    billableOwner,
  ])
  return <WorkbenchContext.Provider value={value}>{children}</WorkbenchContext.Provider>
}
export const WorkbenchContext = createContext<WorkbenchContextData | undefined>(undefined)
export function useWorkbenchContext() {
  const context = useContext(WorkbenchContext)
  if (!context) {
    throw new Error('useWorkbenchContext must be used within a WorkbenchContextProvider')
  }
  return context
}

export type WorkbenchContextData = {
  id: string
  updatedAt?: string
  setUpdatedAt: (value: string) => void
  name: string
  setName: (value: string) => void
  description: string
  setDescription: (value: string) => void
  deployUrl: string
  setDeployUrl: (value: string) => void
  repositoryUrl: string | undefined
  setRepositoryUrl: (value: string) => void
  runtimePermanentName: string
  friendlyName: string
  setFriendlyName: (value: string) => void
  isFetching: boolean
  setIsFetching: (value: boolean) => void
  isOptimisticLoading: boolean
  setIsOptimisticLoading: (value: boolean) => void
  isMobileSidebarOpen: boolean
  setIsMobileSidebarOpen: (value: boolean) => void
  isLoadingFromModel: boolean
  setIsLoadingFromModel: (value: boolean | ((prev: boolean) => boolean)) => void
  initialPromptSubmitted: React.MutableRefObject<boolean>
  iterationStartTime: number | null
  setIterationStartTime: (value: number | null) => void
  userAgentModelPreference: SparkAgentModel
  setUserAgentModelPreference: (value: SparkAgentModel) => void
  sparkAgentModel: SparkAgentModel
  sparkFileUrl: (args: {sparkId: string; path: string}) => string
  sparkBaseUrl: (spark: Workbench | WorkbenchContextData) => string
  billableOwner?: {
    id: number
    login: string
    type: 'User' | 'Organization'
  }
}

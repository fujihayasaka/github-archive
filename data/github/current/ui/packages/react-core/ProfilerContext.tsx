import {isFeatureEnabled} from '@github-ui/feature-flags'
import {noop} from '@github-ui/noop'
import {
  createContext,
  memo,
  Profiler as ReactProfiler,
  type ProfilerOnRenderCallback,
  useCallback,
  useContext,
} from 'react'

function roundTo2DecimalPlaces(value: number): number {
  return Number(value.toFixed(2))
}

export type HandleProfilerOnRender = (
  config: {appName: string; isDataRouterEnabled: boolean},
  ...params: Parameters<ProfilerOnRenderCallback>
) => void
const handleProfilerRender: HandleProfilerOnRender = (
  {appName, isDataRouterEnabled},
  id,
  phase,
  actualDuration,
  baseDuration,
  startTime,
  commitTime,
) => {
  if (typeof window === 'undefined' || !isFeatureEnabled('react_quality_profiling')) {
    return
  }

  const metrics = {
    appName,
    isDataRouterEnabled,
    id,
    phase,
    actualDuration: roundTo2DecimalPlaces(actualDuration),
    baseDuration: roundTo2DecimalPlaces(baseDuration),
    startTime: roundTo2DecimalPlaces(startTime),
    commitTime: roundTo2DecimalPlaces(commitTime),
  }
  // eslint-disable-next-line no-console
  console.groupCollapsed(`[Profiler] ${appName} - ${id} - ${phase}`)
  // eslint-disable-next-line no-console
  console.table(metrics)
  // eslint-disable-next-line no-console
  console.groupEnd()
}

const ProfilerContext = createContext<ProfilerOnRenderCallback | null>(null)
export const ProfilerProvider = memo(function ProfilerProvider({
  onRender,
  isDataRouterEnabled,
  appName,
  children,
}: {
  isDataRouterEnabled: boolean
  onRender?: ProfilerOnRenderCallback
  appName: string
  children: React.ReactNode
}) {
  const defaultProfilerOnRender: ProfilerOnRenderCallback = useCallback(
    (...args) => {
      return handleProfilerRender({appName, isDataRouterEnabled}, ...args)
    },
    [appName, isDataRouterEnabled],
  )

  const activeOnRender = onRender ?? defaultProfilerOnRender
  return <ProfilerContext.Provider value={activeOnRender}>{children}</ProfilerContext.Provider>
})

const useProfilerOnRender = () => {
  const contextValue = useContext(ProfilerContext)
  return contextValue
}

export const Profiler = memo(function Profiler({id, children}: {id: string; children: React.ReactNode}) {
  const profilerOnRender = useProfilerOnRender()
  return (
    <ReactProfiler id={id} onRender={profilerOnRender ?? noop}>
      {children}
    </ReactProfiler>
  )
})

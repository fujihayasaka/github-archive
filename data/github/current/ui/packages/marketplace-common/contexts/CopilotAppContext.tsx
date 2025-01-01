import {createContext, type PropsWithChildren, useContext, useMemo, useState} from 'react'
import {useSearchParams} from '@github-ui/use-navigate'

interface CopilotAppContextType {
  copilotApp: string | null
  setCopilotApp: (copilotApp: string | null) => void
}

const CopilotAppContext = createContext<CopilotAppContextType | undefined>(undefined)

export function useCopilotApp() {
  const context = useContext(CopilotAppContext)
  if (!context) throw new Error('useCopilotApp must be used within a CopilotAppProvider')
  return context
}

export function CopilotAppProvider({children}: PropsWithChildren) {
  const [searchParams] = useSearchParams()
  const [copilotApp, setCopilotApp] = useState<string | null>(() => searchParams.get('copilot_app'))
  const value = useMemo(() => ({copilotApp, setCopilotApp}), [copilotApp, setCopilotApp])
  return <CopilotAppContext.Provider value={value}>{children}</CopilotAppContext.Provider>
}

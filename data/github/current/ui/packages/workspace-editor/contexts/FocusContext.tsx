import {createContext, type PropsWithChildren, useCallback, useContext, useMemo, useRef} from 'react'

type FocusRefElement = HTMLDivElement | HTMLTextAreaElement | null
interface FocusContextData {
  focusTarget: (name: string) => void
  setFocusTarget: (name: string, ref: FocusRefElement) => void
}

const FocusContext = createContext<FocusContextData | undefined>(undefined)

export function FocusContextProvider({children}: PropsWithChildren) {
  const focusTargetsRef = useRef<Map<string, FocusRefElement>>(new Map())

  const focusTarget = useCallback((name: string) => {
    focusTargetsRef.current.get(name)?.focus()
  }, [])

  const setFocusTarget = useCallback((name: string, ref: FocusRefElement) => {
    focusTargetsRef.current.set(name, ref)
  }, [])

  const value = useMemo(() => ({focusTarget, setFocusTarget}), [focusTarget, setFocusTarget])

  return <FocusContext.Provider value={value}>{children}</FocusContext.Provider>
}

export function useFocus() {
  const context = useContext(FocusContext)
  if (!context) {
    throw new Error('useFocus must be used within a FocusProvider')
  }
  return context
}

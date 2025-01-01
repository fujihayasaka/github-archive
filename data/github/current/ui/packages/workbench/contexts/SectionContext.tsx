import React, {useContext, useMemo} from 'react'

export type SectionContext = {
  loading?: boolean
}

export const SectionContext = React.createContext<SectionContext | undefined>(undefined)

export function SectionProvider({children, loading}: React.PropsWithChildren<SectionContext>) {
  const value = useMemo<SectionContext>(
    () => ({
      loading: !!loading,
    }),
    [loading],
  )
  return <SectionContext.Provider value={value}>{children}</SectionContext.Provider>
}

export function useSection() {
  const context = useContext(SectionContext)
  if (!context) {
    throw new Error('useSection must be used within a SectionProvider')
  }
  return context
}

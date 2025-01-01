import {createContext, useCallback, useContext, useMemo, useState, type ReactNode} from 'react'

type IssueTypesMutationErrorsContextType = {
  mutationError: string | null
  setMutationError: (error: string) => void
  clearError: () => void
}

const IssueTypesMutationErrorsContext = createContext<IssueTypesMutationErrorsContextType | null>(null)

export const IssueTypesMutationErrorsProvider = ({children}: {children: ReactNode}) => {
  const [mutationError, setMutationError] = useState<string | null>(null)

  const clearError = useCallback(() => {
    setMutationError(null)
  }, [])

  const value = useMemo(
    () => ({
      mutationError,
      setMutationError,
      clearError,
    }),
    [mutationError, setMutationError, clearError],
  )

  return <IssueTypesMutationErrorsContext.Provider value={value}>{children}</IssueTypesMutationErrorsContext.Provider>
}

export const useIssueTypesMutationErrorsContext = () => {
  const context = useContext(IssueTypesMutationErrorsContext)
  if (!context) {
    throw new Error('useIssueTypesMutationErrorsContext must be used within IssueTypesMutationErrorsProvider')
  }
  return context
}

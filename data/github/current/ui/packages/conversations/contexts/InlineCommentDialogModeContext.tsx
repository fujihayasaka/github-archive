import {createContext, useCallback, useContext, useMemo, useState} from 'react'

type InlineCommentDialogMode = {
  isInDialogMode: boolean
  enableInlineCommentDialogMode: () => void
  disableInlineCommentDialogMode: () => void
}

const InlineCommentDialogModeContext = createContext<InlineCommentDialogMode>({
  isInDialogMode: false,
  enableInlineCommentDialogMode: () => {},
  disableInlineCommentDialogMode: () => {},
})

export function InlineCommmentDialogModeProvider({children}: {children: React.ReactNode}) {
  const [isInDialogMode, setIsInDialogMode] = useState(false)
  const enableInlineCommentDialogMode = useCallback(() => setIsInDialogMode(true), [])
  const disableInlineCommentDialogMode = useCallback(() => setIsInDialogMode(false), [])

  const contextData = useMemo(
    () => ({isInDialogMode, enableInlineCommentDialogMode, disableInlineCommentDialogMode}),
    [isInDialogMode, enableInlineCommentDialogMode, disableInlineCommentDialogMode],
  )

  return (
    <InlineCommentDialogModeContext.Provider value={contextData}>{children}</InlineCommentDialogModeContext.Provider>
  )
}

export const useInlineCommentDialogModeContext = () => useContext(InlineCommentDialogModeContext)

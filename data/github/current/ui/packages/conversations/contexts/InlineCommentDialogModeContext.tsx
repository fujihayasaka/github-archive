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

/**
 * Provider component for the InlineCommentDialogMode context.
 *
 * This provider manages the state of dialog mode for inline comments in diff views.
 * When dialog mode is enabled, interactive elements within annotations and review threads
 * are made accessible to keyboard navigation and screen readers. When disabled, these
 * elements are hidden from keyboard navigation.
 *
 * The provider also coordinates with the diff grid mode through the enableDiffGridMode callback.
 * When dialog mode is enabled, grid mode is disabled and vice versa.
 *
 * @param props.enableDiffGridMode - Optional callback to synchronize the grid mode state with dialog mode.
 *                                  When dialog mode is enabled, this will be called with false.
 *                                  When dialog mode is disabled, this will be called with true.
 * @param props.children - React children to be wrapped by this provider.
 *
 * @example
 * ```tsx
 * <InlineCommentDialogModeProvider enableDiffGridMode={setInGridMode}>
 *   <InlineAnnotation annotation={annotation} />
 * </InlineCommentDialogModeProvider>
 * ```
 */
export function InlineCommentDialogModeProvider({
  enableDiffGridMode,
  children,
}: {
  enableDiffGridMode?: (value: boolean) => void
  children: React.ReactNode
}) {
  const [isInDialogMode, setIsInDialogMode] = useState(false)
  const enableInlineCommentDialogMode = useCallback(() => {
    setIsInDialogMode(true)
    enableDiffGridMode?.(false)
  }, [enableDiffGridMode])

  const disableInlineCommentDialogMode = useCallback(() => {
    setIsInDialogMode(false)
    enableDiffGridMode?.(true)
  }, [enableDiffGridMode])

  const contextData = useMemo(
    () => ({isInDialogMode, enableInlineCommentDialogMode, disableInlineCommentDialogMode}),
    [isInDialogMode, enableInlineCommentDialogMode, disableInlineCommentDialogMode],
  )

  return (
    <InlineCommentDialogModeContext.Provider value={contextData}>{children}</InlineCommentDialogModeContext.Provider>
  )
}

/**
 * Hook to access the InlineCommentDialogMode context.
 *
 * This hook provides access to:
 * - isInDialogMode: Boolean indicating if dialog mode is currently active
 * - enableInlineCommentDialogMode: Function to enable dialog mode
 * - disableInlineCommentDialogMode: Function to disable dialog mode
 *
 * @returns The InlineCommentDialogMode context value
 *
 * @example
 * ```tsx
 * const { isInDialogMode, enableInlineCommentDialogMode } = useInlineCommentDialogModeContext();
 *
 * useEffect(() => {
 *   if (isInDialogMode) {
 *     showInteractiveElements(elementRef.current);
 *   } else {
 *     hideInteractiveElements(elementRef.current);
 *   }
 * }, [isInDialogMode]);
 * ```
 */
export const useInlineCommentDialogModeContext = () => useContext(InlineCommentDialogModeContext)

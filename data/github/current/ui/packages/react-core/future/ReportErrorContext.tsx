// eslint-disable-next-line no-restricted-imports
import {reportError} from '@github-ui/failbot'
import type React from 'react'
import {createContext, memo, useCallback, useContext, useEffect, useRef} from 'react'

import {handleIfNotReported} from './RouterErrorBoundary'

const ReportErrorContext = createContext<typeof reportError | null>(null)

export const ReportErrorContextProvider = memo(function ReportErrorContextProvider({
  appName: reactAppName,
  children,
  critical,
}: React.PropsWithChildren<{appName: string; critical?: boolean}>) {
  const ref = useRef({reactAppName, critical})
  useEffect(() => {
    ref.current = {reactAppName, critical}
  })

  const internalReportError: typeof reportError = useCallback((error, context) => {
    if (!error) return
    return handleIfNotReported(error, err => {
      reportError(err, {
        critical: ref.current.critical,
        reactAppName: ref.current.reactAppName,
        ...context,
      })
      if (process.env.NODE_ENV === 'development') {
        // eslint-disable-next-line no-console
        console.error('Error in InternalResponseErrorElement', error)
      }
    })
    /**
     * this should never get dependencies, since we don't want to re-create the function.
     * This may be called in effects and we want to make sure we don't re-run them if this changes
     * you may need to stash things in the ref above to get the values you need into this method
     * when it's called
     */
  }, [])

  return <ReportErrorContext.Provider value={internalReportError}>{children}</ReportErrorContext.Provider>
})

/**
 *
 * Errors reported in this context will be reported to the failbot service.
 * Do not re-throw the error after calling this function
 *
 * @returns The `reportError` function from `@github-ui/failbot` that can be used to report errors.
 * @throws An error if the context is not used within a `ReportErrorContextProvider`.
 */
export function useReportErrorContext() {
  const reportErrorCtx = useContext(ReportErrorContext)
  if (reportErrorCtx == null) {
    throw new Error('useReportErrorContext must be used within a ReportErrorContextProvider')
  }
  return reportErrorCtx
}

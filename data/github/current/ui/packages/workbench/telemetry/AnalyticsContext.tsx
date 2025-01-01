import type {ILspAnalyticsContextProps} from '@github-ui/workspace-editor/telemetry/interfaces'
import type {PropsWithChildren} from 'react'
import React, {useContext, useEffect, useMemo} from 'react'

import {createSendAnalyticsEvent} from './Event'
import type {GlobalAnalyticsContextProps} from './global/GlobalAnalytics'
import type {Metadata} from './Metadata'

/**
 * Supported analytics context names.
 */
export type AnalyticsContextName = 'global' | 'lsp'

export const AnalyticsContext = React.createContext<Metadata>({})

export type AnalyticsContextProps = GlobalAnalyticsContextProps | ILspAnalyticsContextProps

export function AnalyticsContextProvider({
  children,
  name,
  metadata,
  onStart,
}: PropsWithChildren<AnalyticsContextProps>) {
  const context = useContext(AnalyticsContext)
  const metadataObject = metadata()

  const value = useMemo(() => {
    return {...context, [name]: metadataObject}
  }, [context, name, metadataObject])

  // if the `onStart` callback is provided, call it
  useEffect(() => {
    // if the `onStart` callback is not provided, or it was already called, skip it
    // this is due to the fact that useEffect can actually be called twice, even if
    // the dependency list didn't change; therefore the `onStartRun` object is used
    // to explicitly keep track if the `onStart` callback was indeed already called
    if (typeof onStart !== 'function') {
      return
    }

    onStart(createSendAnalyticsEvent(context))
    // here we do want to depend only on the context `name` variable
    // because it defines the scope of the `onStart` callback, - while
    // the context data might not change, we do want to invoke the function
    // for every other context defined by the name variable
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [name])

  return <AnalyticsContext.Provider value={value}>{children}</AnalyticsContext.Provider>
}

export function useAnalyticsContext() {
  const context = useContext(AnalyticsContext)
  if (!context) {
    throw new Error('useAnalyticsContext must be used within a AnalyticsContextProvider')
  }
  return context
}

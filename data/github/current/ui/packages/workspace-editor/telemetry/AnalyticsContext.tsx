import {type PropsWithChildren, useContext, useEffect, useMemo} from 'react'

import {assertDefined} from '../utilities/asserts'
import type {TAnalyticsContextProps} from './interfaces'
import {AnalyticsMetadata, sendAnalyticsFactory} from './use-analytics'

// Analytics context provider allows to specify scoped metadata for a specific component.
export function AnalyticsContext({children, name, metadata, onStart}: PropsWithChildren<TAnalyticsContextProps>) {
  const contextData = useContext(AnalyticsMetadata)
  assertDefined(contextData, 'No `AnalyticsContext` found.')

  const metadataObject = metadata()
  const context = useMemo(() => {
    return {...contextData, [name]: metadataObject}
  }, [contextData, name, metadataObject])

  // if the `onStart` callback is provided, call it
  useEffect(() => {
    // if the `onStart` callback is not provided, or it was already called, skip it
    // this is due to the fact that useEffect can actually be called twice, even if
    // the dependency list didn't change; therefore the `onStartRun` object is used
    // to explicitly keep track if the `onStart` callback was indeed already called
    if (typeof onStart !== 'function') {
      return
    }

    onStart(sendAnalyticsFactory(context))
    // here we do want to depend only on the context `name` variable
    // because it defines the scope of the `onStart` callback, - while
    // the context data might not change, we do want to invoke the function
    // for every other context defined by the name variable
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [name])

  return <AnalyticsMetadata.Provider value={context}>{children}</AnalyticsMetadata.Provider>
}

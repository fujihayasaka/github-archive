// Think of this as the entry point into the framework
import type {ErrorContext} from '@github-ui/failbot'
import type {ReactPartialAnchorElement} from '@github-ui/react-partial-anchor-element'
import type {History} from '@remix-run/router'
import {RoutesContextProvider} from './RoutesContextProvider'
import {BaseProviders} from './BaseProviders'
import {CommonElements} from './CommonElements'
import {ErrorBoundary} from './ErrorBoundary'
import {PartialRouter} from './PartialRouter'

interface Props<T extends object> {
  partialName: string
  embeddedData: {props: T}
  Component: React.ComponentType<T>
  wasServerRendered: boolean
  ssrError?: HTMLScriptElement
  anchorElement?: ReactPartialAnchorElement | null
  onError?: (error: Error, context?: ErrorContext) => void
  history: History
}

export function PartialEntry<T extends object>({
  partialName,
  embeddedData,
  Component,
  wasServerRendered,
  ssrError,
  onError,
  history,
}: Props<T>) {
  // Wrap the partial in an AppContextProvider and static Router so that react-core links
  // will be functional.
  return (
    <BaseProviders appName={partialName} wasServerRendered={wasServerRendered} dataRouterEnabled={false}>
      <ErrorBoundary onError={onError}>
        <RoutesContextProvider routes={[]}>
          <PartialRouter history={history}>
            <Component {...embeddedData.props} />
            <CommonElements ssrError={ssrError} />
          </PartialRouter>
        </RoutesContextProvider>
      </ErrorBoundary>
    </BaseProviders>
  )
}

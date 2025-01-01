// eslint-disable-next-line no-restricted-imports
import {reportError} from '@github-ui/failbot'
import {Blankslate} from '@primer/react/experimental'
import {useEffect, useRef} from 'react'
import {type ErrorResponse, isRouteErrorResponse, useRouteError} from 'react-router-dom'

import type {ResponseError} from './response-error'
import {isResponseError} from './response-error'
import {useSetTitleOnResponseError} from './use-set-title-on-response-error'

const reportedErrors = new WeakSet<object>()
// This function is used to prevent duplicate error reports for the same error object
// This may happen in StrictMode development
export function handleIfNotReported<T extends object>(error: T, report: (err: T) => void) {
  if (!reportedErrors.has(error)) {
    reportedErrors.add(error)
    report(error)
  }
}

function isNoRouteFoundError(routeError: unknown): routeError is ErrorResponse & {status: 404} {
  return isRouteErrorResponse(routeError) && routeError.status === 404
}
/**
 *
 * Ensure that all render/loader/action errors are handled except a global 404
 * which can only happen in instances where the app is unmounting.
 */
export const UnhandledRouteError = ({appName}: {appName: string}) => {
  const routeError = useRouteError()

  /* when the root route errors with a 404, we're actually navigating _out_ of the app with turbo, but the url updates prior to react being cleaned up */
  if (isNoRouteFoundError(routeError)) {
    return null
  }

  return <BaseRouteErrorBoundary appName={appName} routeError={routeError} />
}

function BaseRouteErrorBoundary({appName, routeError}: {appName: string; routeError: unknown}) {
  // using a ref to avoid running the effect on if appname changes (it can't, but just in case)
  const appNameRef = useRef(appName)
  useEffect(() => {
    appNameRef.current = appName
  })

  useEffect(() => {
    if (routeError) {
      handleIfNotReported(routeError, error => {
        reportError(error, {critical: true, reactAppName: appNameRef.current})
        if (process.env.NODE_ENV === 'development') {
          // eslint-disable-next-line no-console
          console.error('Error in GlobalRouterErrorBoundary', error)
        }
      })
    }
  }, [routeError])

  return (
    <Blankslate border={false} spacious={false}>
      <Blankslate.Heading>Unable to load page.</Blankslate.Heading>
      <Blankslate.Description>Please reload page and try again</Blankslate.Description>
    </Blankslate>
  )
}

/**
 * The RootAppRouteErrorElement is used to handle errors that occur in application code and routes.
 * ResponseErrors (thrown from loaders/actions) are handled by the ResponseErrorElement.
 * All other errors are handled by the BaseRouteErrorBoundary.
 */
export const RootAppRouteErrorElement = ({appName}: {appName: string}) => {
  const routeError = useRouteError()
  if (isResponseError(routeError)) {
    return <ResponseErrorElement appName={appName} responseError={routeError} />
  }

  return <BaseRouteErrorBoundary routeError={routeError} appName={appName} />
}

function ResponseErrorElement({appName, responseError}: {appName: string; responseError: ResponseError}) {
  useSetTitleOnResponseError(responseError)
  // using a ref to avoid running the effect on if appname changes (it can't, but just in case)
  const appNameRef = useRef(appName)
  useEffect(() => {
    appNameRef.current = appName
  })
  useEffect(() => {
    handleIfNotReported(responseError, error => {
      reportError(error, {critical: true, reactAppName: appNameRef.current})
      // in developement, log the error to the console
      if (process.env.NODE_ENV === 'development') {
        // eslint-disable-next-line no-console
        console.error('Error in InternalResponseErrorElement', error)
      }
    })
  }, [responseError])

  return (
    <Blankslate border={false} spacious={false}>
      <Blankslate.Heading>Unable to load page.</Blankslate.Heading>
      <Blankslate.Description>{`Status: ${responseError.response.status} Message: ${responseError.message}`}</Blankslate.Description>
      <Blankslate.Description>Please reload page and try again</Blankslate.Description>
    </Blankslate>
  )
}

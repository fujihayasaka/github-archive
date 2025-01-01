import {isRouteErrorResponse, useRouteError} from 'react-router-dom'
import {useSetTitleOnResponseError} from './use-set-title-on-response-error'
import {isResponseError} from './response-error'
import {Blankslate} from '@primer/react/experimental'

/**
 * By wrapping an application's custom error boundary with this component,
 * applications will get framework level error boundary support, such as
 * updating the title on a navigation error.
 */
export const RouterErrorBoundary = () => {
  const routeError = useRouteError()
  /* when the root route errors with a 404, we're actually navigating _out_ of the app with turbo, but the url updates prior to react being cleaned up */
  if (isRouteErrorResponse(routeError)) {
    if (routeError.status === 404) {
      return null
    }
  }
  return (
    <Blankslate border={false} spacious={false}>
      <Blankslate.Heading>Unable to load page.</Blankslate.Heading>
      <Blankslate.Description>Please reload page and try again</Blankslate.Description>
    </Blankslate>
  )
}

export const ResponseErrorElement = () => {
  useSetTitleOnResponseError()
  const routeError = useRouteError()

  if (isResponseError(routeError)) {
    return (
      <Blankslate border={false} spacious={false}>
        <Blankslate.Heading>Unable to load page.</Blankslate.Heading>
        <Blankslate.Description>{`Status: ${routeError.response.status} Message: ${routeError.message}`}</Blankslate.Description>
        <Blankslate.Description>Please reload page and try again</Blankslate.Description>
      </Blankslate>
    )
  }

  return null
}

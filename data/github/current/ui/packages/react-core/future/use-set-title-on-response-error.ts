import {addGitHubToTitle, setTitle} from '@github-ui/document-metadata'
import {useEffect} from 'react'

import type {ResponseError} from './response-error'

/**
 * If a loader throws a route error, because of a non-OK response, this hook
 * will update the document title based on the status code of the response.
 */
export function useSetTitleOnResponseError(responseError: ResponseError) {
  const responseErrorStatusCode = responseError.response.status
  useEffect(() => {
    const errorTitle = getTitleForStatus(responseErrorStatusCode)
    setTitle(errorTitle)
  }, [responseErrorStatusCode])
}

/**
 * Build a string that can be used for the title, based on a
 * non-OK status code.
 * If the user is logged out, we'll also append "· GitHub"
 */
export function getTitleForStatus(responseStatus: number) {
  const innerTitle =
    responseStatus === 404
      ? '404 Page not found'
      : responseStatus === 500
        ? '500 Internal server error'
        : `Error ${responseStatus}`

  return addGitHubToTitle(innerTitle)
}

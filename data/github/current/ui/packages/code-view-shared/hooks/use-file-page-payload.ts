import type {FilePagePayload} from '@github-ui/code-view-types'
import {extractPathFromPathname} from '@github-ui/paths'
import {useNavigationError} from '@github-ui/react-core/use-navigation-error'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useRef} from 'react'

import {makeErrorPayload} from '../utilities/make-payload'

export function useFilePagePayload(initialPayload?: FilePagePayload): FilePagePayload {
  const routePayload = useRoutePayload<FilePagePayload>()
  let payload = initialPayload || routePayload
  // we assume that the first payload is always good
  const lastGoodPayload = useRef(payload)
  const error = useNavigationError()

  if (!payload) {
    const newPath = extractPathFromPathname(
      location.pathname,
      // eslint-disable-next-line react-compiler/react-compiler
      lastGoodPayload.current.refInfo.name,
      // eslint-disable-next-line react-compiler/react-compiler
      lastGoodPayload.current.path,
    )
    // eslint-disable-next-line react-compiler/react-compiler
    payload = makeErrorPayload(lastGoodPayload.current, error, newPath)
  } else {
    // eslint-disable-next-line react-compiler/react-compiler
    lastGoodPayload.current = payload
  }
  return payload
}

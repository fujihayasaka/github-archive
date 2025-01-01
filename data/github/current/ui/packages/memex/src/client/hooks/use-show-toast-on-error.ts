import {useCallback} from 'react'

import useToasts from '../components/toasts/use-toasts'
import {ApiError} from '../platform/api-error'
import {Resources} from '../strings'

export function useShowToastOnError() {
  const {addToast} = useToasts()
  return useCallback(
    (error: unknown) => {
      if (!(error instanceof ApiError)) {
        // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
        return addToast({type: 'error', message: Resources.genericErrorMessage})
      }

      if (error.status === 503) {
        // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
        return addToast({
          type: 'error',
          message: Resources.serviceUnavailable,
          action: {text: 'Reload', handleClick: () => window.location.reload()},
        })
      }
      // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
      return addToast({type: 'error', message: error.message})
    },
    [addToast],
  )
}

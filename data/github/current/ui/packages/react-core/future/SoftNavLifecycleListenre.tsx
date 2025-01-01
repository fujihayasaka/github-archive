import {memo} from 'react'
import {useLocation, useNavigation} from 'react-router-dom'

import {useSoftNavLifecycle} from '../use-soft-nav-lifecycle'

/**
 * We start the soft nav in the loader and finish it in the router.
 * The soft nav events start via startSoftNav when the loader is called
 * with the request in QueryRoute.
 *
 * SoftNavLifecycleListener is a component that listens to the soft nav
 * lifecycle and finishes the operation when complete.
 */
export const SoftNavLifecycleListener = memo(function SoftNavLifecycleListener() {
  const location = useLocation()
  const navigation = useNavigation()
  const isNavigating = Boolean(navigation.location)
  useSoftNavLifecycle(location, isNavigating, null)
  return null
})

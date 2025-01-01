import {useContext} from 'react'

import {IsDataRouterEnabledContext} from './IsDataRouterEnabled'

export function useIsDataRouterEnabled() {
  return useContext(IsDataRouterEnabledContext)
}

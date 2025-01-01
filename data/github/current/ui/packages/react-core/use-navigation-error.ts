import {useContext} from 'react'

import type {PageError} from './app-routing-types'
import {NavigationErrorContext} from './NavigatorRouter'

export function useNavigationError(): PageError | null {
  return useContext(NavigationErrorContext)
}

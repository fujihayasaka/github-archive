import {createContext} from 'react'

import type {RouteStateMap} from './use-navigator'

export const RouteStateMapContext = createContext<RouteStateMap>({})

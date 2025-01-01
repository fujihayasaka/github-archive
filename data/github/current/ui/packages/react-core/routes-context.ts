import {createContext} from 'react'
import type {RouteObject} from 'react-router-dom'

export interface RoutesContextType {
  routes: RouteObject[]
}

export const RoutesContext = createContext<RoutesContextType>({routes: []})

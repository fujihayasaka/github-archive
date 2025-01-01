import {createContext} from 'react'
import type {AppRegistration} from './react-app-registry'

export interface AppContextType {
  routes: AppRegistration['routes']
}

export const AppContext = createContext<AppContextType>(null as unknown as AppContextType)

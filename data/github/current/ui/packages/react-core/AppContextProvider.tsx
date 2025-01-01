import {useMemo, type PropsWithChildren} from 'react'
import {AppContext, type AppContextType} from './app-context'

export function AppContextProvider({routes, children}: PropsWithChildren<AppContextType>) {
  const appContextProviderValue = useMemo(() => ({routes}), [routes])
  return <AppContext.Provider value={appContextProviderValue}>{children}</AppContext.Provider>
}
